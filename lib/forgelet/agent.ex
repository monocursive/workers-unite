defmodule Forgelet.Agent do
  @moduledoc """
  GenServer representing an AI agent in the Forgelet network.

  Each agent has its own Ed25519 keypair, is registered in the Horde cluster
  registry, and communicates exclusively through signed events appended to the
  EventStore.
  """

  use GenServer

  require Logger

  alias Forgelet.{Event, EventStore, Identity}
  alias Forgelet.Agent.TaskContext
  alias Forgelet.Identity.Provenance

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Spawns a new agent of the given `kind` via the Horde DynamicSupervisor.

  Returns `{:ok, pid, public_key}` on success.

  ## Options

    * `:keypair` — pre-generated keypair; one is created if omitted.
    * `:model` — model name string (e.g. "claude-sonnet-4")
    * `:model_version` — model version string
    * `:capabilities` — list of capability strings
    * `:spawner` — public key of the spawning agent/node
    * Any additional opts are forwarded to `start_link/1`.
  """
  def spawn(kind, opts \\ []) do
    keypair = Keyword.get(opts, :keypair, Identity.generate())
    child_spec = {__MODULE__, Keyword.merge(opts, keypair: keypair, kind: kind)}

    case Horde.DynamicSupervisor.start_child(Forgelet.AgentSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid, keypair.public}
      {:error, _} = error -> error
    end
  end

  @doc false
  def start_link(opts) do
    keypair = Keyword.fetch!(opts, :keypair)

    GenServer.start_link(__MODULE__, opts, name: via(keypair.public))
  end

  @doc """
  Returns the agent's state with the secret key redacted.
  """
  def inspect_state(agent_id) do
    GenServer.call(via(agent_id), :inspect_state)
  end

  @doc """
  Instructs the agent to claim an intent by reference.
  Returns `{:ok, event_ref}` on success.
  """
  def claim_intent(agent_id, intent_ref) do
    GenServer.call(via(agent_id), {:claim_intent_legacy, intent_ref, nil})
  end

  def claim_intent(agent_id, intent_ref, {:repo, _repo_id} = scope) do
    GenServer.call(via(agent_id), {:claim_intent_legacy, intent_ref, scope})
  end

  def claim_intent(agent_id, repo_id, intent_ref) do
    GenServer.call(via(agent_id), {:claim_intent, repo_id, intent_ref, nil})
  end

  def claim_intent(agent_id, repo_id, intent_ref, scope) do
    GenServer.call(via(agent_id), {:claim_intent, repo_id, intent_ref, scope})
  end

  @doc """
  Instructs the agent to submit a proposal with the given payload.
  Returns `{:ok, event_ref}` on success.
  """
  def submit_proposal(agent_id, payload, scope \\ nil) do
    GenServer.call(via(agent_id), {:submit_proposal, payload, scope})
  end

  @doc """
  Starts an autonomous Claude session for the agent.
  """
  def start_session(agent_id, opts \\ []) do
    GenServer.call(via(agent_id), {:start_session, opts})
  end

  @doc """
  Instructs the agent to cast a vote on a proposal.
  Returns `{:ok, event_ref}` on success.
  """
  def vote(agent_id, proposal_ref, verdict, opts \\ []) do
    GenServer.call(via(agent_id), {:vote, proposal_ref, verdict, opts})
  end

  @doc """
  Publishes a repository-scoped intent using the agent's identity.
  """
  def publish_intent(agent_id, repo_id, payload) do
    GenServer.call(via(agent_id), {:publish_intent, repo_id, payload})
  end

  @doc """
  Publishes a repository-scoped review comment.
  """
  def publish_comment(agent_id, payload, scope) do
    GenServer.call(via(agent_id), {:publish_comment, payload, scope})
  end

  @doc """
  Returns a list of `{agent_id, pid}` tuples for all agents registered locally.
  """
  def list_local do
    Horde.Registry.select(Forgelet.Registry, [
      {{{__MODULE__, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp via(agent_id) do
    {:via, Horde.Registry, {Forgelet.Registry, {__MODULE__, agent_id}}}
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    keypair = Keyword.fetch!(opts, :keypair)
    kind = Keyword.fetch!(opts, :kind)

    Phoenix.PubSub.subscribe(Forgelet.PubSub, "events")

    # Publish the join event asynchronously so init doesn't block on EventStore.
    Process.send_after(self(), :publish_joined, 0)

    {:ok,
     %{
       keypair: keypair,
       kind: kind,
       provenance: nil,
       capabilities: [],
       current_task: nil,
       active_session: nil,
       last_session_status: nil,
       last_session_output: nil,
       reputation: 0.5,
       status: :idle,
       model: Keyword.get(opts, :model),
       model_version: Keyword.get(opts, :model_version),
       spawner: Keyword.get(opts, :spawner)
     }}
  end

  @impl true
  def handle_info(:publish_joined, state) do
    case Event.new(:agent_joined, state.keypair, %{"kind" => to_string(state.kind)}) do
      {:ok, joined_event} ->
        safe_append(joined_event, "agent_joined")

      {:error, reason} ->
        Logger.warning("Agent: failed to create agent_joined event: #{inspect(reason)}")
    end

    provenance_attrs = %{
      agent_id: state.keypair.public,
      kind: state.kind,
      created_at: System.os_time(:millisecond),
      model: state.model,
      model_version: state.model_version,
      spawner: state.spawner,
      capabilities: Keyword.get([], :capabilities, [])
    }

    case Provenance.new(provenance_attrs) do
      {:ok, provenance} ->
        # Encode binary fields to hex so the payload is JSON-safe for Postgres.
        prov_payload =
          provenance
          |> Map.from_struct()
          |> Map.new(fn
            {k, v} when is_binary(v) and byte_size(v) > 0 ->
              if String.printable?(v),
                do: {to_string(k), v},
                else: {to_string(k), Base.encode16(v, case: :lower)}

            {k, v} when is_atom(v) ->
              {to_string(k), to_string(v)}

            {k, v} when is_list(v) ->
              {to_string(k), Enum.map(v, &to_string/1)}

            {k, nil} ->
              {to_string(k), nil}

            {k, v} ->
              {to_string(k), v}
          end)

        case Event.new(:agent_provenance, state.keypair, prov_payload) do
          {:ok, prov_event} ->
            safe_append(prov_event, "agent_provenance")

          {:error, reason} ->
            Logger.warning("Agent: failed to create provenance event: #{inspect(reason)}")
        end

        {:noreply, %{state | provenance: provenance}}

      {:error, reason} ->
        Logger.warning("Agent: failed to create provenance: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:event, %{kind: :consensus_reached} = event}, state) do
    # Only reset if this consensus is about our current task
    proposal_ref = event.payload["proposal_ref"]

    if match?(%{kind: :proposal, ref: ^proposal_ref}, state.current_task) do
      {:noreply, %{state | status: :idle, current_task: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:session_ended, _session_pid, session_status, output}, state) do
    publish_session_event(state, session_status, output)

    next_status =
      if is_nil(state.current_task) do
        :idle
      else
        state.status
      end

    {:noreply,
     %{
       state
       | active_session: nil,
         status: next_status,
         last_session_status: session_status,
         last_session_output: output
     }}
  end

  @impl true
  def handle_info({:event, %{kind: :capability_granted} = event}, state) do
    agent_id = event.payload["agent_id"]

    if agent_id == state.keypair.public do
      capability = event.payload["capability"]
      {:noreply, %{state | capabilities: [capability | state.capabilities]}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:event, _}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:claim_intent_legacy, intent_ref, scope}, _from, state) do
    repo_id =
      case scope do
        {:repo, repo_id} -> repo_id
        _ -> nil
      end

    do_claim_intent(state, repo_id, intent_ref, scope)
  end

  @impl true
  def handle_call({:claim_intent, repo_id, intent_ref, scope}, _from, state) do
    do_claim_intent(state, repo_id, intent_ref, scope)
  end

  @impl true
  def handle_call({:start_session, opts}, _from, state) do
    cond do
      state.active_session ->
        {:reply, {:error, :session_already_active}, state}

      state.status not in [:idle, :working] ->
        {:reply, {:error, :agent_unavailable}, state}

      true ->
        with {:ok, task_context} <- TaskContext.resolve(state),
             {:ok, session_pid, session_token} <-
               Forgelet.Agent.Session.start_for_agent(
                 self(),
                 state.keypair.public,
                 state.kind,
                 Keyword.put(opts, :task_context, task_context)
               ) do
          {:reply, {:ok, session_pid, session_token},
           %{
             state
             | active_session: %{pid: session_pid, token: session_token},
               status: :working
           }}
        else
          {:error, _} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:submit_proposal, payload, scope}, _from, state) do
    opts = if scope, do: [scope: scope], else: []

    # Add references if intent_ref is in the payload
    opts =
      case payload["intent_ref"] do
        nil -> opts
        ref -> Keyword.put(opts, :references, [{:intent, ref}])
      end

    case Event.new(:proposal_submitted, state.keypair, payload, opts) do
      {:ok, event} ->
        case EventStore.append(event) do
          {:ok, stored} ->
            repo_id =
              case scope do
                {:repo, scoped_repo_id} -> scoped_repo_id
                _ -> Map.get(payload, "repo_id")
              end

            {:reply, {:ok, Event.ref(stored)},
             %{
               state
               | current_task: %{repo_id: repo_id, kind: :proposal, ref: Event.ref(stored)},
                 status: :working
             }}

          {:error, _} = error ->
            {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:publish_intent, repo_id, payload}, _from, state) do
    case Forgelet.Repository.publish_intent(repo_id, state.keypair, payload) do
      {:ok, event} -> {:reply, {:ok, Event.ref(event)}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:publish_comment, payload, scope}, _from, state) do
    opts = if scope, do: [scope: scope], else: []

    case Event.new(:comment_added, state.keypair, payload, opts) do
      {:ok, event} ->
        case EventStore.append(event) do
          {:ok, stored} -> {:reply, {:ok, Event.ref(stored)}, state}
          {:error, _} = error -> {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:vote, proposal_ref, verdict, opts}, _from, state) do
    scope = Keyword.get(opts, :scope)
    confidence = Keyword.get(opts, :confidence, 1.0)

    vote_payload = %{
      "proposal_ref" => proposal_ref,
      "verdict" => to_string(verdict),
      "confidence" => confidence
    }

    event_opts =
      [references: [{:proposal, proposal_ref}]] ++
        if(scope, do: [scope: scope], else: [])

    case Event.new(:vote_cast, state.keypair, vote_payload, event_opts) do
      {:ok, event} ->
        case EventStore.append(event) do
          {:ok, stored} ->
            {:reply, {:ok, Event.ref(stored)}, state}

          {:error, _} = error ->
            {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:inspect_state, _from, state) do
    sanitized =
      state
      |> Map.put(:keypair, %{public: state.keypair.public})
      |> Map.update!(:active_session, fn
        nil -> nil
        session -> Map.delete(session, :pid)
      end)

    {:reply, sanitized, state}
  end

  defp do_claim_intent(state, repo_id, intent_ref, scope) do
    opts =
      if scope,
        do: [scope: scope, references: [{:intent, intent_ref}]],
        else: [references: [{:intent, intent_ref}]]

    with :ok <- maybe_reserve_claim(repo_id, intent_ref, state.keypair.public),
         {:ok, event} <-
           Event.new(:intent_claimed, state.keypair, %{"intent_ref" => intent_ref}, opts) do
      case EventStore.append(event) do
        {:ok, stored} ->
          {:reply, {:ok, Event.ref(stored)},
           %{
             state
             | status: :working,
               current_task: %{repo_id: repo_id, kind: :intent, ref: intent_ref}
           }}

        {:error, _} = error ->
          :ok = maybe_release_claim(repo_id, intent_ref, state.keypair.public)
          {:reply, error, state}
      end
    else
      {:error, _} = error ->
        {:reply, error, state}

      :ok ->
        {:reply, {:error, :unexpected_reservation_result}, state}

      other ->
        {:reply, other, state}
    end
  end

  defp maybe_reserve_claim(nil, _intent_ref, _agent_id), do: :ok

  defp maybe_reserve_claim(repo_id, intent_ref, agent_id) do
    Forgelet.Repository.reserve_intent_claim(repo_id, intent_ref, agent_id)
  end

  defp maybe_release_claim(nil, _intent_ref, _agent_id), do: :ok

  defp maybe_release_claim(repo_id, intent_ref, agent_id) do
    Forgelet.Repository.release_intent_claim(repo_id, intent_ref, agent_id)
  end

  defp publish_session_event(state, session_status, output) do
    event_kind =
      case session_status do
        :completed -> :session_completed
        _ -> :session_failed
      end

    payload = %{
      "status" => to_string(session_status),
      "summary" => String.slice(output || "", 0, 500),
      "task_ref" => state.current_task && state.current_task.ref
    }

    case Event.new(event_kind, state.keypair, payload) do
      {:ok, event} ->
        safe_append(event, Atom.to_string(event_kind))
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp safe_append(event, label) do
    case EventStore.append(event) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Agent: failed to append #{label}: #{inspect(reason)}")
    end
  catch
    :exit, reason ->
      Logger.warning("Agent: append #{label} exited: #{inspect(reason)}")
      :ok
  end
end

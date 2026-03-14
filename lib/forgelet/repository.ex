defmodule Forgelet.Repository do
  @moduledoc """
  GenServer representing a code repository in the Forgelet network.

  Each repository is a Horde-distributed process registered via
  `Forgelet.Registry` and supervised by `Forgelet.RepoSupervisor`.
  It tracks intents, proposals, and participating agents, reacting to
  events broadcast over PubSub.
  """

  use GenServer

  require Logger

  alias Forgelet.{Event, EventStore, Git}

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new repository, starts it under `Forgelet.RepoSupervisor`, and
  returns `{:ok, pid, repo_id}`.
  """
  def create(name, owner_keypair, opts \\ []) do
    repo_id = :crypto.hash(:sha256, name <> :crypto.strong_rand_bytes(16))

    child_spec =
      {__MODULE__, Keyword.merge(opts, name: name, owner: owner_keypair, repo_id: repo_id)}

    case Horde.DynamicSupervisor.start_child(Forgelet.RepoSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid, repo_id}
      {:error, _} = error -> error
    end
  end

  @doc false
  def start_link(opts) do
    repo_id = Keyword.fetch!(opts, :repo_id)
    GenServer.start_link(__MODULE__, opts, name: via(repo_id))
  end

  @doc """
  Returns the (sanitized) state of the repository identified by `repo_id`.
  """
  def get_state(repo_id) do
    GenServer.call(via(repo_id), :get_state)
  end

  @doc """
  Returns open, unclaimed intents for a repository.
  """
  def list_open_intents(repo_id) do
    GenServer.call(via(repo_id), :list_open_intents)
  end

  @doc """
  Returns proposals still pending review for a repository.
  """
  def list_active_proposals(repo_id) do
    GenServer.call(via(repo_id), :list_active_proposals)
  end

  @doc """
  Reserves an intent claim before the authoring agent emits the signed event.
  """
  def reserve_intent_claim(repo_id, intent_ref, agent_id) do
    GenServer.call(via(repo_id), {:reserve_intent_claim, intent_ref, agent_id})
  end

  @doc """
  Releases an intent claim reservation if event publication fails.
  """
  def release_intent_claim(repo_id, intent_ref, agent_id) do
    GenServer.call(via(repo_id), {:release_intent_claim, intent_ref, agent_id})
  end

  @doc """
  Publishes an intent scoped to the given repository.
  """
  def publish_intent(repo_id, keypair, payload) do
    GenServer.call(via(repo_id), {:publish_intent, keypair, payload})
  end

  @doc """
  Lists all repositories currently registered in `Forgelet.Registry`.
  """
  def list_local do
    Horde.Registry.select(Forgelet.Registry, [
      {{{__MODULE__, :"$1"}, :"$2", :"$3"}, [], [%{repo_id: :"$1", pid: :"$2"}]}
    ])
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp via(repo_id) do
    {:via, Horde.Registry, {Forgelet.Registry, {__MODULE__, repo_id}}}
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    owner = Keyword.fetch!(opts, :owner)
    repo_id = Keyword.fetch!(opts, :repo_id)

    repo_base_path = Application.get_env(:forgelet, :repo_base_path, "priv/repos")
    hex_id = Base.encode16(repo_id, case: :lower)
    path = Path.join(repo_base_path, hex_id)
    File.mkdir_p!(path)

    # Initialize bare git repo
    case System.cmd("git", ["init", "--bare"], cd: path, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> Logger.warning("Repository: git init --bare failed: #{output}")
    end

    ensure_initial_commit(path)

    scope = {:repo, repo_id}

    Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:scope:repo:#{hex_id}")
    Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:kind:consensus_reached")

    # Publish the :repo_created event asynchronously so the GenServer finishes init first.
    Process.send_after(self(), :publish_created, 0)

    policy = Application.get_env(:forgelet, :default_consensus_policy, {:threshold, 2, 0.7})

    {:ok,
     %{
       id: repo_id,
       name: name,
       path: path,
       owner: owner,
       policy: policy,
       active_intents: %{},
       intent_claims: %{},
       reserved_claims: %{},
       active_proposals: %{},
       proposal_statuses: %{},
       agents: MapSet.new(),
       scope: scope,
       created_at: System.os_time(:millisecond)
     }}
  end

  @impl true
  def handle_info(:publish_created, state) do
    case Event.new(:repo_created, state.owner, %{"name" => state.name}, scope: state.scope) do
      {:ok, event} ->
        case EventStore.append(event) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Repository: failed to append repo_created: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Repository: failed to create repo_created event: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:event, %{kind: :intent_published} = event}, state) do
    intent_ref = Event.ref(event)
    {:noreply, %{state | active_intents: Map.put(state.active_intents, intent_ref, event)}}
  end

  def handle_info({:event, %{kind: :intent_claimed} = event}, state) do
    agent_key = event.author
    intent_ref = event.payload["intent_ref"]

    updated_claims =
      if is_binary(intent_ref) do
        Map.put(state.intent_claims, intent_ref, agent_key)
      else
        state.intent_claims
      end

    updated_reservations =
      if is_binary(intent_ref) do
        Map.delete(state.reserved_claims, intent_ref)
      else
        state.reserved_claims
      end

    {:noreply,
     %{
       state
       | agents: MapSet.put(state.agents, agent_key),
         intent_claims: updated_claims,
         reserved_claims: updated_reservations
     }}
  end

  def handle_info({:event, %{kind: :proposal_submitted} = event}, state) do
    # Store proposals by hex-encoded ref for consistent matching
    proposal_ref = Event.ref(event)

    {:noreply,
     %{
       state
       | active_proposals: Map.put(state.active_proposals, proposal_ref, event),
         proposal_statuses: Map.put(state.proposal_statuses, proposal_ref, :pending)
     }}
  end

  def handle_info({:event, %{kind: :proposal_withdrawn} = event}, state) do
    proposal_ref = event.payload["proposal_ref"]

    {:noreply,
     %{
       state
       | active_proposals: Map.delete(state.active_proposals, proposal_ref),
         proposal_statuses: Map.put(state.proposal_statuses, proposal_ref, :withdrawn)
     }}
  end

  def handle_info({:event, %{kind: :consensus_reached} = event}, state) do
    proposal_ref = event.payload["proposal_ref"]
    outcome = event.payload["outcome"]

    if Map.has_key?(state.active_proposals, proposal_ref) do
      proposal_event = Map.fetch!(state.active_proposals, proposal_ref)
      append_merge_result(state, proposal_ref, outcome, proposal_event)

      {:noreply,
       %{
         state
         | active_proposals: Map.delete(state.active_proposals, proposal_ref),
           proposal_statuses:
             Map.put(state.proposal_statuses, proposal_ref, normalize_outcome(outcome))
       }}
    else
      {:noreply, state}
    end
  end

  def handle_info({:event, _}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:get_state, _from, state) do
    sanitized = %{state | owner: %{public: state.owner.public}}
    {:reply, sanitized, state}
  end

  def handle_call(:list_open_intents, _from, state) do
    intents =
      state.active_intents
      |> Enum.reject(fn {intent_ref, _event} ->
        Map.has_key?(state.intent_claims, intent_ref) or
          Map.has_key?(state.reserved_claims, intent_ref)
      end)
      |> Enum.map(fn {_intent_ref, event} -> event end)

    {:reply, intents, state}
  end

  def handle_call(:list_active_proposals, _from, state) do
    proposals =
      state.active_proposals
      |> Enum.filter(fn {proposal_ref, _event} ->
        Map.get(state.proposal_statuses, proposal_ref, :pending) == :pending
      end)
      |> Enum.map(fn {_proposal_ref, event} -> event end)

    {:reply, proposals, state}
  end

  def handle_call({:reserve_intent_claim, intent_ref, agent_id}, _from, state) do
    cond do
      not Map.has_key?(state.active_intents, intent_ref) ->
        {:reply, {:error, :intent_not_found}, state}

      Map.has_key?(state.intent_claims, intent_ref) ->
        {:reply, {:error, :already_claimed}, state}

      Map.has_key?(state.reserved_claims, intent_ref) ->
        {:reply, {:error, :already_claimed}, state}

      true ->
        {:reply, :ok,
         %{state | reserved_claims: Map.put(state.reserved_claims, intent_ref, agent_id)}}
    end
  end

  def handle_call({:release_intent_claim, intent_ref, agent_id}, _from, state) do
    reserved_by = Map.get(state.reserved_claims, intent_ref)

    if reserved_by == agent_id do
      {:reply, :ok, %{state | reserved_claims: Map.delete(state.reserved_claims, intent_ref)}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:publish_intent, keypair, payload}, _from, state) do
    case Event.new(:intent_published, keypair, payload, scope: state.scope) do
      {:ok, event} ->
        case EventStore.append(event) do
          {:ok, _} ->
            updated_intents = Map.put(state.active_intents, Event.ref(event), event)
            {:reply, {:ok, event}, %{state | active_intents: updated_intents}}

          {:error, _} = error ->
            {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp normalize_outcome(outcome) when outcome in [:accepted, "accepted"], do: :accepted
  defp normalize_outcome(outcome) when outcome in [:rejected, "rejected"], do: :rejected
  defp normalize_outcome(_outcome), do: :pending

  defp append_merge_result(state, proposal_ref, outcome, proposal_event) do
    result =
      if outcome in [:accepted, "accepted"] do
        execute_merge(state, proposal_ref, proposal_event)
      else
        {:ok, :merge_rejected,
         %{"proposal_ref" => proposal_ref, "reason" => "consensus_rejected"}}
      end

    case result do
      {:ok, result_kind, payload} ->
        append_repo_event(state, result_kind, payload)

      {:error, reason} ->
        append_repo_event(state, :merge_rejected, %{
          "proposal_ref" => proposal_ref,
          "reason" => inspect(reason)
        })
    end
  end

  defp execute_merge(state, proposal_ref, proposal_event) do
    with %{"artifact" => artifact} <- proposal_event.payload,
         {:ok, branch_name} <- mergeable_branch_name(artifact),
         {:ok, new_head} <- merge_branch_into_main(state.path, branch_name) do
      append_repo_event(state, :repo_ref_updated, %{
        "proposal_ref" => proposal_ref,
        "branch" => Git.default_branch(),
        "head" => new_head
      })

      {:ok, :merge_executed,
       %{"proposal_ref" => proposal_ref, "branch" => branch_name, "head" => new_head}}
    else
      nil -> {:error, :missing_artifact}
      {:error, reason} -> {:error, reason}
    end
  end

  defp mergeable_branch_name(%{"type" => "branch", "name" => branch_name})
       when is_binary(branch_name) do
    {:ok, branch_name}
  end

  defp mergeable_branch_name(%{"type" => "commit_range"}) do
    {:error, :commit_range_merge_not_supported}
  end

  defp mergeable_branch_name(_artifact), do: {:error, :unsupported_artifact}

  defp merge_branch_into_main(bare_repo_path, branch_name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "forgelet-merge-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)

    try do
      with :ok <- Git.clone(bare_repo_path, tmp_dir),
           :ok <- Git.configure_identity(tmp_dir, "Forgelet", "forgelet@example.local"),
           :ok <- Git.fetch_all(tmp_dir),
           :ok <-
             Git.checkout_branch(tmp_dir, Git.default_branch(), "origin/#{Git.default_branch()}"),
           :ok <- Git.merge_remote_branch(tmp_dir, branch_name),
           :ok <- Git.push_ref(tmp_dir, Git.default_branch(), Git.default_branch()),
           {:ok, head} <- Git.rev_parse(tmp_dir, "HEAD") do
        {:ok, head}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp append_repo_event(state, kind, payload) do
    case Event.new(kind, state.owner, payload, scope: state.scope) do
      {:ok, repo_event} ->
        case EventStore.append(repo_event) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Repository: failed to append #{kind}: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Repository: failed to create #{kind}: #{inspect(reason)}")
    end
  end

  defp ensure_initial_commit(bare_repo_path) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "forgelet-bootstrap-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)

    try do
      with {_, 0} <- System.cmd("git", ["clone", bare_repo_path, tmp_dir], stderr_to_stdout: true),
           {_, 0} <-
             System.cmd("git", ["config", "user.name", "Forgelet"],
               cd: tmp_dir,
               stderr_to_stdout: true
             ),
           {_, 0} <-
             System.cmd("git", ["config", "user.email", "forgelet@example.local"],
               cd: tmp_dir,
               stderr_to_stdout: true
             ),
           {_, 0} <-
             System.cmd("git", ["commit", "--allow-empty", "-m", "Initial commit"],
               cd: tmp_dir,
               stderr_to_stdout: true
             ),
           {_, 0} <-
             System.cmd("git", ["push", "origin", "HEAD:main"],
               cd: tmp_dir,
               stderr_to_stdout: true
             ),
           {_, 0} <-
             System.cmd("git", ["symbolic-ref", "HEAD", "refs/heads/main"],
               cd: bare_repo_path,
               stderr_to_stdout: true
             ) do
        :ok
      else
        {output, _code} ->
          Logger.warning("Repository: initial commit bootstrap failed: #{output}")
      end
    after
      File.rm_rf(tmp_dir)
    end
  end
end

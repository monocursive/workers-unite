defmodule WorkersUnite.Consensus.Engine do
  @moduledoc """
  Consensus engine that watches for votes and evaluates whether
  consensus has been reached on proposals.
  """

  use GenServer

  alias WorkersUnite.Consensus.Policy
  alias WorkersUnite.EventStore

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def set_policy(scope, policy, name \\ __MODULE__) do
    GenServer.call(name, {:set_policy, scope, policy})
  end

  def evaluate(proposal_ref, name \\ __MODULE__) do
    GenServer.call(name, {:evaluate, proposal_ref})
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(WorkersUnite.PubSub, "events:kind:vote_cast")

    default_policy =
      Application.get_env(:workers_unite, :default_consensus_policy, {:threshold, 0.5})

    {:ok, %{policies: %{}, default_policy: default_policy}}
  end

  @impl true
  def handle_call({:set_policy, scope, policy}, _from, state) do
    {:reply, :ok, put_in(state.policies[scope], policy)}
  end

  @impl true
  def handle_call({:evaluate, proposal_ref}, _from, state) do
    result = do_evaluate(proposal_ref, state)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:event, %{kind: :vote_cast} = event}, state) do
    proposal_ref = event.payload["proposal_ref"]

    if proposal_ref do
      case do_evaluate(proposal_ref, state) do
        {:ok, outcome} when outcome in [:accepted, :rejected] ->
          publish_consensus_reached(proposal_ref, outcome, event.scope)

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp do_evaluate(proposal_ref, state) do
    votes =
      EventStore.by_kind(:vote_cast)
      |> Enum.filter(fn e ->
        ref = e.payload["proposal_ref"]
        ref == proposal_ref
      end)
      |> Enum.map(fn e ->
        verdict_raw = e.payload["verdict"]

        verdict =
          case verdict_raw do
            v when v in [:accept, :reject, :abstain] -> v
            "accept" -> :accept
            "reject" -> :reject
            "abstain" -> :abstain
            other -> raise "Unknown verdict: #{inspect(other)}"
          end

        weight =
          case e.payload["weight"] do
            nil -> 1.0
            w -> w
          end

        %{verdict: verdict, weight: weight, author: e.author}
      end)

    policy = Map.get(state.policies, proposal_ref, state.default_policy)
    {:ok, Policy.evaluate(policy, votes)}
  end

  defp publish_consensus_reached(proposal_ref, outcome, scope) do
    vault = WorkersUnite.Identity.Vault
    public = vault.public_key()

    payload = %{
      "proposal_ref" => proposal_ref,
      "outcome" => to_string(outcome)
    }

    canonical = %{
      kind: :consensus_reached,
      author: public,
      payload: payload,
      timestamp: System.os_time(:millisecond),
      references: [{:proposal, proposal_ref}],
      scope: scope
    }

    bytes = :erlang.term_to_binary(canonical, [:deterministic])
    id = :crypto.hash(:sha256, bytes)
    signature = vault.sign(bytes)

    event = %WorkersUnite.Event{
      id: id,
      kind: :consensus_reached,
      author: public,
      payload: payload,
      timestamp: canonical.timestamp,
      signature: signature,
      references: canonical.references,
      scope: scope
    }

    EventStore.append(event)
  rescue
    e ->
      require Logger
      Logger.error("Consensus.Engine: failed to publish consensus_reached: #{inspect(e)}")
      {:error, e}
  end
end

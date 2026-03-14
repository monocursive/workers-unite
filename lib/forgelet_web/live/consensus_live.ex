defmodule ForgeletWeb.ConsensusLive do
  use ForgeletWeb, :live_view

  alias Forgelet.{EventStore, Identity}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:kind:vote_cast")
      Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:kind:consensus_reached")
      Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:kind:proposal_submitted")
    end

    votes = EventStore.by_kind(:vote_cast)
    consensus = EventStore.by_kind(:consensus_reached)
    proposals = EventStore.by_kind(:proposal_submitted)

    decided_refs =
      consensus
      |> Enum.map(fn e -> e.payload["proposal_ref"] end)
      |> MapSet.new()

    active_proposals =
      proposals
      |> Enum.reject(fn p -> MapSet.member?(decided_refs, Forgelet.Event.ref(p)) end)

    {:ok,
     assign(socket,
       page_title: "Consensus",
       votes: votes,
       consensus: consensus |> Enum.reverse(),
       active_proposals: active_proposals,
       decided_refs: decided_refs
     )}
  end

  @impl true
  def handle_info({:event, %{kind: kind} = event}, socket)
      when kind in [:vote_cast, :consensus_reached, :proposal_submitted] do
    votes =
      if kind == :vote_cast,
        do: socket.assigns.votes ++ [event],
        else: socket.assigns.votes

    consensus =
      if kind == :consensus_reached,
        do: [event | socket.assigns.consensus],
        else: socket.assigns.consensus

    decided_refs =
      consensus
      |> Enum.map(fn e -> e.payload["proposal_ref"] end)
      |> MapSet.new()

    active_proposals =
      if kind == :proposal_submitted do
        if MapSet.member?(decided_refs, Forgelet.Event.ref(event)),
          do: socket.assigns.active_proposals,
          else: socket.assigns.active_proposals ++ [event]
      else
        Enum.reject(socket.assigns.active_proposals, fn p ->
          MapSet.member?(decided_refs, Forgelet.Event.ref(p))
        end)
      end

    {:noreply,
     assign(socket,
       votes: votes,
       consensus: consensus,
       active_proposals: active_proposals,
       decided_refs: decided_refs
     )}
  end

  def handle_info({:event, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <h1 class="text-2xl font-bold">Consensus</h1>

        <div>
          <h2 class="text-lg font-semibold mb-4">Active Proposals</h2>
          <div class="space-y-4">
            <div
              :for={proposal <- @active_proposals}
              class="card bg-base-200 p-4 space-y-3"
            >
              <div class="flex items-center gap-3">
                <span class="badge badge-warning">pending</span>
                <span class="font-mono text-xs">
                  {Base.encode16(proposal.id, case: :lower) |> String.slice(0..15)}
                </span>
                <span class="text-sm opacity-60 ml-auto">{format_timestamp(proposal.timestamp)}</span>
              </div>
              <div class="text-sm">
                <span class="opacity-70">Author:</span>
                <span class="font-mono">{Identity.fingerprint(proposal.author)}</span>
              </div>
              <div class="text-sm">
                <% votes_for = votes_for_proposal(@votes, Forgelet.Event.ref(proposal)) %>
                <% accept_count =
                  Enum.count(votes_for, fn v ->
                    v.payload["verdict"] in ["accept", "accepted"]
                  end) %>
                <% reject_count =
                  Enum.count(votes_for, fn v ->
                    v.payload["verdict"] in ["reject", "rejected"]
                  end) %>
                <% total = length(votes_for) %>
                <div class="flex items-center gap-4">
                  <span class="text-success">Accept: {accept_count}</span>
                  <span class="text-error">Reject: {reject_count}</span>
                  <span class="opacity-70">Total: {total}</span>
                </div>
                <div :if={total > 0} class="w-full bg-base-300 rounded-full h-2 mt-2">
                  <div
                    class="bg-success h-2 rounded-full"
                    style={"width: #{if total > 0, do: trunc(accept_count / total * 100), else: 0}%"}
                  >
                  </div>
                </div>
              </div>
            </div>
            <p :if={@active_proposals == []} class="text-sm opacity-60">No active proposals.</p>
          </div>
        </div>

        <div>
          <h2 class="text-lg font-semibold mb-4">Completed Decisions</h2>
          <div class="space-y-3">
            <div
              :for={decision <- @consensus}
              class="card bg-base-200 p-4 flex flex-row items-center gap-4"
            >
              <span class={"badge #{outcome_color(decision.payload)}"}>
                {decision.payload["outcome"]}
              </span>
              <span class="font-mono text-xs">
                {format_ref(decision.payload["proposal_ref"])}
              </span>
              <span class="font-mono text-sm">{Identity.fingerprint(decision.author)}</span>
              <span class="text-sm opacity-60 ml-auto">{format_timestamp(decision.timestamp)}</span>
            </div>
            <p :if={@consensus == []} class="text-sm opacity-60">No consensus decisions yet.</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp votes_for_proposal(votes, proposal_ref) do
    Enum.filter(votes, fn v ->
      v.payload["proposal_ref"] == proposal_ref
    end)
  end

  defp outcome_color(payload) do
    case to_string(payload["outcome"]) do
      "accepted" -> "badge-success"
      "rejected" -> "badge-error"
      _ -> "badge-ghost"
    end
  end

  defp format_ref(ref) when is_binary(ref) do
    String.slice(ref, 0..15)
  end

  defp format_ref(ref), do: inspect(ref)

  defp format_timestamp(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_timestamp(_), do: "---"
end

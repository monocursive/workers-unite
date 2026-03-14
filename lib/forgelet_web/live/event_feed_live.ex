defmodule ForgeletWeb.EventFeedLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Real-time event firehose displaying all events from the EventStore with
  live updates via PubSub and filterable by event kind.
  """

  alias Forgelet.{EventStore, Identity}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Forgelet.PubSub, "events")
    end

    events = EventStore.stream() |> Enum.reverse()

    {:ok,
     assign(socket,
       page_title: "Event Feed",
       events: events,
       filter_kind: nil
     )}
  end

  @impl true
  def handle_event("filter", %{"kind" => ""}, socket) do
    {:noreply, assign(socket, filter_kind: nil)}
  end

  def handle_event("filter", %{"kind" => kind}, socket) do
    atom =
      try do
        String.to_existing_atom(kind)
      rescue
        ArgumentError -> nil
      end

    {:noreply, assign(socket, filter_kind: atom)}
  end

  @impl true
  def handle_info({:event, event}, socket) do
    {:noreply, assign(socket, events: [event | socket.assigns.events])}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :filtered_events, filtered_events(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Event Feed</h1>

        <div class="flex flex-wrap gap-2">
          <button
            phx-click="filter"
            phx-value-kind=""
            class={"btn btn-sm #{if @filter_kind == nil, do: "btn-primary", else: "btn-ghost"}"}
          >
            All
          </button>
          <button
            :for={kind <- common_kinds()}
            phx-click="filter"
            phx-value-kind={kind}
            class={"btn btn-sm #{if @filter_kind == kind, do: "btn-primary", else: "btn-ghost"}"}
          >
            {kind}
          </button>
        </div>

        <div class="space-y-3">
          <div
            :for={event <- @filtered_events}
            class="card bg-base-200 p-4 space-y-2"
          >
            <div class="flex items-center gap-3 flex-wrap">
              <span class="badge badge-primary">{event.kind}</span>
              <span class="font-mono text-xs">{Base.encode16(event.id, case: :lower)}</span>
              <span class="text-sm opacity-60 ml-auto">{format_timestamp(event.timestamp)}</span>
            </div>
            <div class="text-sm">
              <span class="opacity-70">Author:</span>
              <span class="font-mono">{Identity.fingerprint(event.author)}</span>
            </div>
            <div :if={event.scope} class="text-sm">
              <span class="opacity-70">Scope:</span>
              <span class="font-mono">{format_scope(event.scope)}</span>
            </div>
            <div :if={event.references != []} class="text-sm">
              <span class="opacity-70">References:</span>
              <span :for={ref <- event.references} class="font-mono text-xs ml-1">
                {format_reference(ref)}
              </span>
            </div>
            <div class="text-sm">
              <span class="opacity-70">Payload:</span>
              <pre class="text-xs bg-base-300 p-2 rounded mt-1 overflow-x-auto">{inspect(event.payload, pretty: true)}</pre>
            </div>
          </div>
          <p :if={@filtered_events == []} class="text-sm opacity-60">No events to display.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp filtered_events(%{filter_kind: nil, events: events}), do: events

  defp filtered_events(%{filter_kind: kind, events: events}) do
    Enum.filter(events, &(&1.kind == kind))
  end

  defp common_kinds do
    [
      :agent_joined,
      :repo_created,
      :intent_published,
      :intent_claimed,
      :proposal_submitted,
      :vote_cast,
      :consensus_reached,
      :merge_executed
    ]
  end

  defp format_timestamp(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_timestamp(_), do: "---"

  defp format_reference({type, id}) when is_binary(id) do
    "#{type}:#{id}"
  end

  defp format_reference(ref) when is_binary(ref) do
    Base.encode16(ref, case: :lower)
  rescue
    _ -> inspect(ref)
  end

  defp format_reference(ref), do: inspect(ref)

  defp format_scope({type, id}) when is_binary(id) do
    "#{type}:#{Base.encode16(id, case: :lower)}"
  end

  defp format_scope(scope), do: inspect(scope)
end

defmodule WorkersUniteWeb.DashboardLive do
  use WorkersUniteWeb, :live_view

  @moduledoc """
  Main dashboard showing system overview with event, agent, and repository counts,
  plus a live-updating feed of the 20 most recent events.
  """

  alias WorkersUnite.{EventStore, Agent, Repository, Identity}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WorkersUnite.PubSub, "events")
    end

    events = EventStore.stream()
    recent = events |> Enum.reverse() |> Enum.take(20)

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       event_count: EventStore.count(),
       agent_count: length(Agent.list_local()),
       repo_count: length(Repository.list_local()),
       recent_events: recent
     )}
  end

  @impl true
  def handle_info({:event, event}, socket) do
    recent =
      [event | socket.assigns.recent_events]
      |> Enum.take(20)

    {:noreply,
     assign(socket,
       event_count: socket.assigns.event_count + 1,
       recent_events: recent
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <h1 class="text-2xl font-bold">Mission Control</h1>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div class="card bg-base-200 p-6">
            <div class="text-sm opacity-70">Events</div>
            <div class="text-3xl font-bold">{@event_count}</div>
          </div>
          <div class="card bg-base-200 p-6">
            <div class="text-sm opacity-70">Agents</div>
            <div class="text-3xl font-bold">{@agent_count}</div>
          </div>
          <div class="card bg-base-200 p-6">
            <div class="text-sm opacity-70">Repos</div>
            <div class="text-3xl font-bold">{@repo_count}</div>
          </div>
        </div>

        <div>
          <h2 class="text-lg font-semibold mb-4">Recent Events</h2>
          <div class="space-y-2">
            <div
              :for={event <- @recent_events}
              class="card bg-base-200 p-3 flex flex-row items-center gap-4"
            >
              <span class="badge badge-primary">{event.kind}</span>
              <span class="font-mono text-sm">{Identity.fingerprint(event.author)}</span>
              <span class="text-sm opacity-60 ml-auto">{format_timestamp(event.timestamp)}</span>
            </div>
            <p :if={@recent_events == []} class="text-sm opacity-60">No events yet.</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_timestamp(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_timestamp(_), do: "---"
end

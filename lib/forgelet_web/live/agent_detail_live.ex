defmodule ForgeletWeb.AgentDetailLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Shows an individual agent's identity, status, capabilities, provenance,
  and a live-updating history of events authored by that agent.
  """

  alias Forgelet.{Agent, EventStore, Identity}

  @impl true
  def mount(%{"id" => hex_id}, _session, socket) do
    case Base.decode16(hex_id, case: :lower) do
      {:ok, public_key} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:author:#{hex_id}")
        end

        state =
          try do
            Agent.inspect_state(public_key)
          catch
            :exit, _ -> nil
          end

        if state do
          events = EventStore.by_author(public_key) |> Enum.reverse()

          {:ok,
           assign(socket,
             page_title: "Agent #{hex_id}",
             hex_id: hex_id,
             public_key: public_key,
             agent_state: state,
             events: events
           )}
        else
          {:ok,
           socket
           |> put_flash(:error, "Agent not found or unavailable")
           |> push_navigate(to: ~p"/agents")}
        end

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid agent ID")
         |> push_navigate(to: ~p"/agents")}
    end
  end

  @impl true
  def handle_info({:event, event}, socket) do
    {:noreply, assign(socket, events: [event | socket.assigns.events])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <a href={~p"/agents"} class="btn btn-ghost btn-sm">Back</a>
          <h1 class="text-2xl font-bold">Agent Detail</h1>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="card bg-base-200 p-4 space-y-3">
            <h2 class="font-semibold">Identity</h2>
            <div class="text-sm">
              <span class="opacity-70">Fingerprint:</span>
              <span class="font-mono">{Identity.fingerprint(@public_key)}</span>
            </div>
            <div class="text-sm">
              <span class="opacity-70">Public Key:</span>
              <span class="font-mono text-xs break-all">{@hex_id}</span>
            </div>
          </div>

          <div class="card bg-base-200 p-4 space-y-3">
            <h2 class="font-semibold">Status</h2>
            <div class="text-sm">
              <span class="opacity-70">Kind:</span>
              <span class="badge badge-sm">{@agent_state.kind}</span>
            </div>
            <div class="text-sm">
              <span class="opacity-70">Status:</span>
              <span class="badge badge-sm">{@agent_state.status}</span>
            </div>
            <div class="text-sm">
              <span class="opacity-70">Reputation:</span>
              <span>{@agent_state.reputation}</span>
            </div>
          </div>
        </div>

        <div :if={@agent_state.capabilities != []} class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">Capabilities</h2>
          <div class="flex flex-wrap gap-2">
            <span :for={cap <- @agent_state.capabilities} class="badge badge-primary badge-sm">
              {cap}
            </span>
          </div>
        </div>

        <div :if={@agent_state.provenance} class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">Provenance</h2>
          <pre class="text-xs bg-base-300 p-2 rounded overflow-x-auto">{inspect(@agent_state.provenance, pretty: true)}</pre>
        </div>

        <div>
          <h2 class="font-semibold mb-4">Event History</h2>
          <div class="space-y-2">
            <div
              :for={event <- @events}
              class="card bg-base-200 p-3 flex flex-row items-center gap-4"
            >
              <span class="badge badge-primary badge-sm">{event.kind}</span>
              <span class="font-mono text-xs">
                {Base.encode16(event.id, case: :lower) |> String.slice(0..15)}
              </span>
              <span class="text-sm opacity-60 ml-auto">{format_timestamp(event.timestamp)}</span>
            </div>
            <p :if={@events == []} class="text-sm opacity-60">No events from this agent.</p>
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

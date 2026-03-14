defmodule WorkersUniteWeb.RepoDetailLive do
  use WorkersUniteWeb, :live_view

  @moduledoc """
  Shows an individual repository's details including active intents, proposals,
  participating agents, and a live-updating scoped event log.
  """

  alias WorkersUnite.{Repository, EventStore, Identity}

  @impl true
  def mount(%{"id" => hex_id}, _session, socket) do
    case Base.decode16(hex_id, case: :lower) do
      {:ok, repo_id} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(WorkersUnite.PubSub, "events:scope:repo:#{hex_id}")
        end

        state =
          try do
            Repository.get_state(repo_id)
          catch
            :exit, _ -> nil
          end

        if state do
          events = EventStore.by_scope({:repo, repo_id}) |> Enum.reverse()

          {:ok,
           assign(socket,
             page_title: "Repo: #{state.name}",
             hex_id: hex_id,
             repo_id: repo_id,
             repo_state: state,
             events: events
           )}
        else
          {:ok,
           socket
           |> put_flash(:error, "Repository not found or unavailable")
           |> push_navigate(to: ~p"/repos")}
        end

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid repository ID")
         |> push_navigate(to: ~p"/repos")}
    end
  end

  @impl true
  def handle_info({:event, event}, socket) do
    repo_id = socket.assigns.repo_id

    # Refresh state on relevant events
    state =
      try do
        Repository.get_state(repo_id)
      catch
        :exit, _ -> socket.assigns.repo_state
      end

    events = [event | socket.assigns.events]

    {:noreply, assign(socket, repo_state: state, events: events)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <a href={~p"/repos"} class="btn btn-ghost btn-sm">Back</a>
          <h1 class="text-2xl font-bold">{@repo_state.name}</h1>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="card bg-base-200 p-4 space-y-2">
            <h2 class="font-semibold">Info</h2>
            <div class="text-sm">
              <span class="opacity-70">ID:</span>
              <span class="font-mono text-xs break-all">{@hex_id}</span>
            </div>
            <div class="text-sm">
              <span class="opacity-70">Policy:</span>
              <span>{inspect(@repo_state.policy)}</span>
            </div>
          </div>

          <div class="card bg-base-200 p-4 space-y-2">
            <h2 class="font-semibold">Intents ({map_size(@repo_state.active_intents)})</h2>
            <div
              :for={{id, intent} <- @repo_state.active_intents}
              class="text-sm border-b border-base-300 pb-1"
            >
              <span class="font-mono text-xs">
                {Base.encode16(id, case: :lower) |> String.slice(0..15)}
              </span>
              <span class="opacity-70 ml-2">{inspect(intent.payload)}</span>
            </div>
            <p :if={@repo_state.active_intents == %{}} class="text-sm opacity-60">
              No active intents.
            </p>
          </div>

          <div class="card bg-base-200 p-4 space-y-2">
            <h2 class="font-semibold">Proposals ({map_size(@repo_state.active_proposals)})</h2>
            <div
              :for={{id, proposal} <- @repo_state.active_proposals}
              class="text-sm border-b border-base-300 pb-1"
            >
              <span class="font-mono text-xs">
                {Base.encode16(id, case: :lower) |> String.slice(0..15)}
              </span>
              <span class="opacity-70 ml-2">{Identity.fingerprint(proposal.author)}</span>
            </div>
            <p :if={@repo_state.active_proposals == %{}} class="text-sm opacity-60">
              No active proposals.
            </p>
          </div>
        </div>

        <div class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">Agents ({MapSet.size(@repo_state.agents)})</h2>
          <div class="flex flex-wrap gap-2">
            <span
              :for={agent_key <- MapSet.to_list(@repo_state.agents)}
              class="badge badge-sm font-mono"
            >
              {Identity.fingerprint(agent_key)}
            </span>
          </div>
          <p :if={MapSet.size(@repo_state.agents) == 0} class="text-sm opacity-60">
            No agents participating.
          </p>
        </div>

        <div>
          <h2 class="font-semibold mb-4">Scoped Event Log</h2>
          <div class="space-y-2">
            <div
              :for={event <- @events}
              class="card bg-base-200 p-3 flex flex-row items-center gap-4"
            >
              <span class="badge badge-primary badge-sm">{event.kind}</span>
              <span class="font-mono text-sm">{Identity.fingerprint(event.author)}</span>
              <span class="text-sm opacity-60 ml-auto">{format_timestamp(event.timestamp)}</span>
            </div>
            <p :if={@events == []} class="text-sm opacity-60">No scoped events.</p>
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

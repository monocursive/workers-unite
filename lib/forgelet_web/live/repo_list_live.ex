defmodule ForgeletWeb.RepoListLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Lists all repositories on the local node with their names, agent counts,
  and active intent counts. Updates live when new repositories are created.
  """

  alias Forgelet.Repository

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:kind:repo_created")
    end

    repos = load_repos()

    {:ok,
     assign(socket,
       page_title: "Repositories",
       repos: repos
     )}
  end

  @impl true
  def handle_info({:event, %{kind: :repo_created}}, socket) do
    {:noreply, assign(socket, repos: load_repos())}
  end

  def handle_info({:event, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Repositories</h1>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <a
            :for={repo <- @repos}
            href={~p"/repos/#{repo.hex_id}"}
            class="card bg-base-200 p-4 space-y-2 hover:bg-base-300 transition-colors"
          >
            <div class="font-semibold">{repo.name}</div>
            <div class="flex items-center gap-3 text-sm">
              <span class="opacity-70">{repo.agent_count} agents</span>
              <span class="opacity-70">{repo.intent_count} intents</span>
            </div>
          </a>
        </div>

        <p :if={@repos == []} class="text-sm opacity-60">No repositories created.</p>
      </div>
    </Layouts.app>
    """
  end

  defp load_repos do
    Repository.list_local()
    |> Enum.map(fn %{repo_id: repo_id} ->
      state = Repository.get_state(repo_id)

      %{
        repo_id: repo_id,
        hex_id: Base.encode16(repo_id, case: :lower),
        name: state.name,
        agent_count: MapSet.size(state.agents),
        intent_count: map_size(state.active_intents)
      }
    end)
  rescue
    _ -> []
  end
end

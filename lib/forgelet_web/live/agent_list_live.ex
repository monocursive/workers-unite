defmodule ForgeletWeb.AgentListLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Lists all active agents on the local node with their fingerprints, kinds,
  and statuses. Updates in real time when new agents join.
  """

  alias Forgelet.{Agent, Identity}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Forgelet.PubSub, "events:kind:agent_joined")
    end

    agents = load_agents()

    {:ok,
     assign(socket,
       page_title: "Agents",
       agents: agents
     )}
  end

  @impl true
  def handle_info({:event, %{kind: :agent_joined}}, socket) do
    {:noreply, assign(socket, agents: load_agents())}
  end

  def handle_info({:event, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Agents</h1>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <a
            :for={agent <- @agents}
            href={~p"/agents/#{agent.hex_id}"}
            class="card bg-base-200 p-4 space-y-2 hover:bg-base-300 transition-colors"
          >
            <div class="font-mono text-sm">{agent.fingerprint}</div>
            <div class="flex items-center gap-2">
              <span class="badge badge-sm">{agent.kind}</span>
              <span class={"badge badge-sm #{status_color(agent.status)}"}>{agent.status}</span>
            </div>
          </a>
        </div>

        <p :if={@agents == []} class="text-sm opacity-60">No agents registered.</p>
      </div>
    </Layouts.app>
    """
  end

  defp load_agents do
    Agent.list_local()
    |> Enum.map(fn {public_key, _pid} ->
      state = Agent.inspect_state(public_key)

      %{
        public_key: public_key,
        hex_id: Base.encode16(public_key, case: :lower),
        fingerprint: Identity.fingerprint(public_key),
        kind: state.kind,
        status: state.status
      }
    end)
  rescue
    _ -> []
  end

  defp status_color(:idle), do: "badge-ghost"
  defp status_color(:working), do: "badge-success"
  defp status_color(_), do: "badge-ghost"
end

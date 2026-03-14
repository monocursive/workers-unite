defmodule WorkersUniteWeb.MCP.Tools.GetAgentState do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Agent, Identity}

  @impl true
  def definition do
    %{
      "name" => "workers_unite_get_state",
      "description" => "Returns the authenticated agent's state.",
      "inputSchema" => %{"type" => "object", "properties" => %{}}
    }
  end

  @impl true
  def call(_params, %{agent_id: agent_id}) do
    state = Agent.inspect_state(agent_id)

    {:ok,
     %{
       kind: state.kind,
       status: state.status,
       reputation: state.reputation,
       capabilities: state.capabilities,
       current_task: state.current_task,
       fingerprint: Identity.fingerprint(agent_id),
       active_session: state.active_session
     }}
  end
end

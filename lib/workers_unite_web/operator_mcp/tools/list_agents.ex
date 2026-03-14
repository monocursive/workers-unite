defmodule WorkersUniteWeb.OperatorMCP.Tools.ListAgents do
  @moduledoc """
  Lists all agents registered on this WorkersUnite instance with their current state.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Agent, Identity}

  @impl true
  def definition do
    %{
      "name" => "wu_list_agents",
      "description" =>
        "Lists all AI agents on this WorkersUnite instance. Returns each agent's " <>
          "fingerprint, kind, status, reputation, current task, and model.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of agents to return (default 100)"
          }
        }
      }
    }
  end

  @impl true
  def call(params, _context) do
    limit = parse_limit(params)

    agents =
      Agent.list_local()
      |> Enum.flat_map(fn {agent_id, _pid} ->
        try do
          state = Agent.inspect_state(agent_id)

          [
            %{
              fingerprint: Identity.fingerprint(agent_id),
              kind: state.kind,
              status: state.status,
              reputation: state.reputation,
              current_task: state.current_task,
              model: state.model
            }
          ]
        catch
          :exit, _reason -> []
        end
      end)
      |> Enum.take(limit)

    {:ok, agents}
  end

  defp parse_limit(%{"limit" => l}) when is_integer(l) and l > 0, do: min(l, 100)
  defp parse_limit(_), do: 100
end

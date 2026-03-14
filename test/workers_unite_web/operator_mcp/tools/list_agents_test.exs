defmodule WorkersUniteWeb.OperatorMCP.Tools.ListAgentsTest do
  use ExUnit.Case, async: true

  alias WorkersUniteWeb.OperatorMCP.Tools.ListAgents

  test "definition returns expected tool metadata" do
    defn = ListAgents.definition()
    assert defn["name"] == "wu_list_agents"
    assert is_binary(defn["description"])
    assert defn["inputSchema"]["properties"]["limit"]["type"] == "integer"
  end
end

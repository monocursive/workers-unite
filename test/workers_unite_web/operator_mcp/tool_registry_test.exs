defmodule WorkersUniteWeb.OperatorMCP.ToolRegistryTest do
  use ExUnit.Case, async: true

  alias WorkersUniteWeb.OperatorMCP.ToolRegistry

  @observe_tool_names ~w(
    wu_list_agents wu_inspect_agent wu_list_repos wu_inspect_repo
    wu_query_events wu_list_intents wu_list_proposals wu_inspect_consensus
    wu_get_proposal_diff wu_list_sessions
  )

  @control_tool_names ~w(
    wu_publish_intent wu_claim_intent wu_dispatch_work
    wu_publish_comment wu_cast_vote wu_cancel_session
  )

  describe "list_for_scopes/1" do
    test "returns only observe tool definitions for observe scope" do
      definitions = ToolRegistry.list_for_scopes(["observe"])
      names = Enum.map(definitions, & &1["name"])

      assert length(names) == length(@observe_tool_names)

      for name <- @observe_tool_names do
        assert name in names
      end

      for name <- @control_tool_names do
        refute name in names
      end
    end

    test "returns only control tool definitions for control scope" do
      definitions = ToolRegistry.list_for_scopes(["control"])
      names = Enum.map(definitions, & &1["name"])

      assert length(names) == length(@control_tool_names)

      for name <- @control_tool_names do
        assert name in names
      end

      for name <- @observe_tool_names do
        refute name in names
      end
    end

    test "returns all tools for both observe and control scopes" do
      definitions = ToolRegistry.list_for_scopes(["observe", "control"])
      names = Enum.map(definitions, & &1["name"])
      all_names = @observe_tool_names ++ @control_tool_names

      assert length(names) == length(all_names)

      for name <- all_names do
        assert name in names
      end
    end

    test "returns empty list for empty scopes" do
      assert ToolRegistry.list_for_scopes([]) == []
    end

    test "each definition includes name, description, and inputSchema" do
      definitions = ToolRegistry.list_for_scopes(["observe", "control"])

      for definition <- definitions do
        assert Map.has_key?(definition, "name")
        assert Map.has_key?(definition, "description")
        assert Map.has_key?(definition, "inputSchema")
        assert is_binary(definition["name"])
        assert is_binary(definition["description"])
        assert is_map(definition["inputSchema"])
      end
    end
  end

  describe "dispatch/3" do
    test "returns {:error, :unauthorized} when scope does not match" do
      context = %{scopes: ["observe"]}

      assert {:error, :unauthorized} =
               ToolRegistry.dispatch("wu_publish_intent", %{}, context)
    end

    test "returns {:error, :unauthorized} for control tool with observe-only scope" do
      context = %{scopes: ["observe"]}

      for name <- @control_tool_names do
        assert {:error, :unauthorized} = ToolRegistry.dispatch(name, %{}, context)
      end
    end

    test "returns {:error, :unauthorized} for observe tool with control-only scope" do
      context = %{scopes: ["control"]}

      for name <- @observe_tool_names do
        assert {:error, :unauthorized} = ToolRegistry.dispatch(name, %{}, context)
      end
    end

    test "returns {:error, :tool_not_found} for unknown tool name" do
      context = %{scopes: ["observe", "control"]}

      assert {:error, :tool_not_found} =
               ToolRegistry.dispatch("wu_nonexistent_tool", %{}, context)
    end

    test "returns {:error, :unauthorized} with empty scopes for any tool" do
      context = %{scopes: []}

      assert {:error, :unauthorized} =
               ToolRegistry.dispatch("wu_list_agents", %{}, context)

      assert {:error, :unauthorized} =
               ToolRegistry.dispatch("wu_publish_intent", %{}, context)
    end
  end
end

defmodule WorkersUniteWeb.OperatorMCP.Tools.QueryEventsTest do
  use WorkersUnite.DataCase

  alias WorkersUniteWeb.OperatorMCP.Tools.QueryEvents
  alias WorkersUnite.{EventStore, EventHelpers}

  setup do
    # Ensure EventStore is running and has a clean table for these tests
    events_exist =
      try do
        EventStore.count()
        true
      catch
        _, _ -> false
      end

    unless events_exist do
      start_supervised!({EventStore, table: :query_events_test})
    end

    :ok
  end

  test "definition returns expected tool metadata" do
    defn = QueryEvents.definition()
    assert defn["name"] == "wu_query_events"
    assert defn["inputSchema"]["properties"]["kind"]
    assert defn["inputSchema"]["properties"]["limit"]
  end

  test "call with no filters returns events" do
    {:ok, events} = QueryEvents.call(%{}, %{})
    assert is_list(events)
  end

  test "call with limit constrains results" do
    {:ok, events} = QueryEvents.call(%{"limit" => 1}, %{})
    assert length(events) <= 1
  end

  test "call with invalid kind returns empty" do
    {:ok, events} = QueryEvents.call(%{"kind" => "nonexistent_event_kind_xyz"}, %{})
    assert events == []
  end
end

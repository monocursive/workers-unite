defmodule WorkersUniteWeb.OperatorMCP.Tools.PublishIntentTest do
  use WorkersUnite.DataCase

  alias WorkersUniteWeb.OperatorMCP.Tools.PublishIntent

  test "definition returns expected tool metadata" do
    defn = PublishIntent.definition()
    assert defn["name"] == "wu_publish_intent"
    assert defn["inputSchema"]["required"] == ["repo_id", "title"]
  end

  test "call with missing params returns error" do
    assert {:error, :invalid_params} = PublishIntent.call(%{}, %{user_id: "test"})
  end

  test "call with invalid repo_id returns error" do
    result =
      PublishIntent.call(
        %{"repo_id" => "not_valid_hex!", "title" => "Test"},
        %{user_id: "test"}
      )

    assert {:error, :invalid_repo_id} = result
  end

  test "call with valid hex repo_id but no repo running returns repo_not_found" do
    result =
      PublishIntent.call(
        %{
          "repo_id" => "0000000000000000000000000000000000000000000000000000000000000000",
          "title" => "Test intent"
        },
        %{user_id: "test"}
      )

    assert {:error, :repo_not_found} = result
  end
end

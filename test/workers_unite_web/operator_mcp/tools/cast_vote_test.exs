defmodule WorkersUniteWeb.OperatorMCP.Tools.CastVoteTest do
  use WorkersUnite.DataCase

  alias WorkersUniteWeb.OperatorMCP.Tools.CastVote

  test "definition returns expected tool metadata" do
    defn = CastVote.definition()
    assert defn["name"] == "wu_cast_vote"
    assert defn["inputSchema"]["required"] == ["proposal_ref", "verdict", "confidence"]
  end

  test "call with invalid verdict returns error" do
    result = CastVote.call(%{"verdict" => "maybe", "confidence" => 0.5}, %{user_id: "test"})
    assert {:error, {:invalid_verdict, _}} = result
  end

  test "call with invalid confidence returns error" do
    result = CastVote.call(%{"confidence" => 1.5}, %{user_id: "test"})
    assert {:error, {:invalid_confidence, _}} = result
  end

  test "call with missing params returns error" do
    assert {:error, :invalid_params} = CastVote.call(%{}, %{user_id: "test"})
  end

  test "call with non-existent proposal returns error" do
    result =
      CastVote.call(
        %{
          "proposal_ref" => "0000000000000000000000000000000000000000000000000000000000000000",
          "verdict" => "accept",
          "confidence" => 0.9
        },
        %{user_id: "test"}
      )

    assert {:error, :proposal_not_found} = result
  end
end

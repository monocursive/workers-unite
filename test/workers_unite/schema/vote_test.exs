defmodule WorkersUnite.Schema.VoteTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Schema

  describe "vote_cast" do
    test "valid event passes" do
      event = %{
        kind: :vote_cast,
        payload: %{"proposal_ref" => "prop_123", "verdict" => "accept"}
      }

      assert :ok = Schema.validate(event)
    end

    test "atom verdict passes" do
      event = %{
        kind: :vote_cast,
        payload: %{"proposal_ref" => "prop_123", "verdict" => :reject}
      }

      assert :ok = Schema.validate(event)
    end

    test "abstain verdict passes" do
      event = %{
        kind: :vote_cast,
        payload: %{"proposal_ref" => "prop_123", "verdict" => "abstain"}
      }

      assert :ok = Schema.validate(event)
    end

    test "missing proposal_ref fails" do
      event = %{
        kind: :vote_cast,
        payload: %{"verdict" => "accept"}
      }

      assert {:error, "missing required field: proposal_ref"} = Schema.validate(event)
    end

    test "missing verdict fails" do
      event = %{
        kind: :vote_cast,
        payload: %{"proposal_ref" => "prop_123"}
      }

      assert {:error, "missing required field: verdict"} = Schema.validate(event)
    end

    test "invalid verdict fails" do
      event = %{
        kind: :vote_cast,
        payload: %{"proposal_ref" => "prop_123", "verdict" => "maybe"}
      }

      assert {:error, "verdict must be one of: accept, reject, abstain"} = Schema.validate(event)
    end
  end
end

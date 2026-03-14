defmodule WorkersUnite.Consensus.PolicyTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Consensus.Policy

  describe "evaluate_threshold/3" do
    test "accepts when enough accept votes" do
      votes = [%{verdict: :accept}, %{verdict: :accept}, %{verdict: :reject}]
      assert Policy.evaluate_threshold(0.5, votes, 1) == :accepted
    end

    test "rejects when enough reject votes" do
      votes = [%{verdict: :reject}, %{verdict: :reject}, %{verdict: :accept}]
      assert Policy.evaluate_threshold(0.5, votes, 1) == :rejected
    end

    test "pending when not enough votes" do
      votes = [%{verdict: :accept}]
      assert Policy.evaluate_threshold(0.5, votes, 3) == :pending
    end

    test "pending when not enough decisive votes" do
      # 1 accept only, threshold 0.75 but need at least 3 votes
      votes = [%{verdict: :accept}]
      assert Policy.evaluate_threshold(0.75, votes, 3) == :pending
    end
  end

  describe "evaluate_unanimous/2" do
    test "accepts when all accept" do
      votes = [%{verdict: :accept}, %{verdict: :accept}]
      assert Policy.evaluate_unanimous(2, votes) == :accepted
    end

    test "rejects when any reject" do
      votes = [%{verdict: :accept}, %{verdict: :reject}]
      assert Policy.evaluate_unanimous(2, votes) == :rejected
    end

    test "pending when not enough accepts" do
      votes = [%{verdict: :accept}]
      assert Policy.evaluate_unanimous(2, votes) == :pending
    end
  end

  describe "evaluate_weighted/2" do
    test "accepts when weighted score above threshold" do
      votes = [
        %{verdict: :accept, weight: 3.0},
        %{verdict: :reject, weight: 1.0}
      ]

      assert Policy.evaluate_weighted(0.5, votes) == :accepted
    end

    test "rejects when weighted reject above threshold" do
      votes = [
        %{verdict: :reject, weight: 3.0},
        %{verdict: :accept, weight: 1.0}
      ]

      assert Policy.evaluate_weighted(0.5, votes) == :rejected
    end

    test "pending with no votes" do
      assert Policy.evaluate_weighted(0.5, []) == :pending
    end
  end

  describe "evaluate/2 dispatch" do
    test "dispatches threshold (3-tuple)" do
      votes = [%{verdict: :accept}, %{verdict: :accept}]
      assert Policy.evaluate({:threshold, 2, 0.5}, votes) == :accepted
    end

    test "threshold requires min_votes" do
      votes = [%{verdict: :accept}]
      assert Policy.evaluate({:threshold, 2, 0.5}, votes) == :pending
    end

    test "dispatches unanimous" do
      votes = [%{verdict: :accept}, %{verdict: :accept}]
      assert Policy.evaluate({:unanimous, 2}, votes) == :accepted
    end

    test "dispatches weighted" do
      votes = [%{verdict: :accept, weight: 1.0}]
      assert Policy.evaluate({:weighted, 0.5}, votes) == :accepted
    end
  end
end

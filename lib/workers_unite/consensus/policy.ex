defmodule WorkersUnite.Consensus.Policy do
  @moduledoc """
  Pure functions for evaluating consensus based on votes and policy configuration.
  """

  @doc """
  Evaluate votes against a policy configuration.
  Returns `:accepted`, `:rejected`, or `:pending`.
  """
  def evaluate({:threshold, min_votes, min_confidence}, votes) do
    evaluate_threshold(min_confidence, votes, min_votes)
  end

  def evaluate({:unanimous, expected_count}, votes) do
    evaluate_unanimous(expected_count, votes)
  end

  def evaluate({:weighted, threshold}, votes) do
    evaluate_weighted(threshold, votes)
  end

  def evaluate({:custom, module}, votes) do
    module.evaluate(votes)
  end

  @doc """
  Threshold-based consensus: accepted if accept ratio >= threshold.
  """
  def evaluate_threshold(threshold, votes, min_votes) do
    if length(votes) < min_votes do
      :pending
    else
      accepts = Enum.count(votes, &(&1.verdict == :accept))
      rejects = Enum.count(votes, &(&1.verdict == :reject))
      total = accepts + rejects

      cond do
        total == 0 -> :pending
        accepts / total >= threshold -> :accepted
        rejects / total > 1 - threshold -> :rejected
        true -> :pending
      end
    end
  end

  @doc """
  Unanimous consensus: all voters must accept.
  """
  def evaluate_unanimous(expected_count, votes) do
    accepts = Enum.count(votes, &(&1.verdict == :accept))
    rejects = Enum.count(votes, &(&1.verdict == :reject))

    cond do
      rejects > 0 -> :rejected
      accepts >= expected_count -> :accepted
      true -> :pending
    end
  end

  @doc """
  Weighted consensus: sum of weighted votes meets threshold.
  Each vote should have a :weight field (defaults to 1.0).
  """
  def evaluate_weighted(threshold, votes) do
    total_weight = Enum.reduce(votes, 0.0, fn v, acc -> acc + Map.get(v, :weight, 1.0) end)

    accept_weight =
      votes
      |> Enum.filter(&(&1.verdict == :accept))
      |> Enum.reduce(0.0, fn v, acc -> acc + Map.get(v, :weight, 1.0) end)

    reject_weight =
      votes
      |> Enum.filter(&(&1.verdict == :reject))
      |> Enum.reduce(0.0, fn v, acc -> acc + Map.get(v, :weight, 1.0) end)

    cond do
      total_weight == 0 -> :pending
      accept_weight / total_weight >= threshold -> :accepted
      reject_weight / total_weight > 1 - threshold -> :rejected
      true -> :pending
    end
  end
end

defmodule WorkersUnite.Schema.Vote do
  @moduledoc """
  Validates payloads for vote events.
  """

  @valid_verdicts ["accept", "reject", "abstain", :accept, :reject, :abstain]

  @doc """
  Validates a vote_cast event's payload.

  Requires `proposal_ref` (binary) and `verdict` (one of "accept", "reject",
  "abstain" as strings or atoms). Optional `confidence` (float 0.0..1.0).

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(%{kind: atom(), payload: map()}) :: :ok | {:error, String.t()}
  def validate(%{kind: :vote_cast, payload: payload}) do
    with :ok <- require_binary(payload, "proposal_ref"),
         :ok <- validate_verdict(payload),
         :ok <- validate_confidence(payload) do
      :ok
    end
  end

  defp validate_verdict(payload) do
    case Map.get(payload, "verdict") do
      verdict when verdict in @valid_verdicts -> :ok
      nil -> {:error, "missing required field: verdict"}
      _ -> {:error, "verdict must be one of: accept, reject, abstain"}
    end
  end

  defp validate_confidence(payload) do
    case Map.get(payload, "confidence") do
      nil -> :ok
      c when is_number(c) and c >= 0.0 and c <= 1.0 -> :ok
      c when is_number(c) -> {:error, "confidence must be between 0.0 and 1.0"}
      _ -> {:error, "confidence must be a number"}
    end
  end

  defp require_binary(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a binary"}
    end
  end
end

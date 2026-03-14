defmodule WorkersUnite.Schema.Intent do
  @moduledoc """
  Validates payloads for intent-related events.
  """

  @doc """
  Validates an intent event's payload.

  - `:intent_published` — requires `title` (string).
  - `:intent_claimed` — requires `intent_ref` (binary).
  - `:intent_updated` — requires `intent_ref` (binary).
  - `:intent_cancelled` — requires `intent_ref` (binary).

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(%{kind: atom(), payload: map()}) :: :ok | {:error, String.t()}
  def validate(%{kind: :intent_published, payload: payload}) do
    with :ok <- require_string(payload, "title"),
         :ok <- validate_optional_string(payload, "description"),
         :ok <- validate_optional_priority(payload),
         :ok <- validate_optional_tags(payload) do
      :ok
    end
  end

  def validate(%{kind: :intent_claimed, payload: payload}) do
    require_binary(payload, "intent_ref")
  end

  def validate(%{kind: :intent_updated, payload: payload}) do
    require_binary(payload, "intent_ref")
  end

  def validate(%{kind: :intent_cancelled, payload: payload}) do
    require_binary(payload, "intent_ref")
  end

  defp require_string(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) and byte_size(value) > 0 -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a non-empty string"}
    end
  end

  defp require_binary(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a binary"}
    end
  end

  defp validate_optional_string(payload, key) do
    case Map.get(payload, key) do
      nil -> :ok
      value when is_binary(value) -> :ok
      _ -> {:error, "#{key} must be a string"}
    end
  end

  defp validate_optional_priority(payload) do
    case Map.get(payload, "priority") do
      nil -> :ok
      value when is_number(value) and value >= 0.0 and value <= 1.0 -> :ok
      value when is_number(value) -> {:error, "priority must be between 0.0 and 1.0"}
      _ -> {:error, "priority must be a number"}
    end
  end

  defp validate_optional_tags(payload) do
    case Map.get(payload, "tags") do
      nil ->
        :ok

      tags when is_list(tags) ->
        if Enum.all?(tags, &is_binary/1),
          do: :ok,
          else: {:error, "tags must be a list of strings"}

      _ ->
        {:error, "tags must be a list of strings"}
    end
  end
end

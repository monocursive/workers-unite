defmodule WorkersUnite.Schema.Capability do
  @moduledoc """
  Validates payloads for capability-related events.
  """

  @doc """
  Validates a capability event's payload.

  - `:capability_granted` — requires `grantee` (binary), `scope`, and
    `permissions` (list).
  - `:capability_revoked` — requires `grantee` (binary).

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(%{kind: atom(), payload: map()}) :: :ok | {:error, String.t()}
  def validate(%{kind: :capability_granted, payload: payload}) do
    with :ok <- require_binary(payload, "grantee"),
         :ok <- require_present(payload, "scope"),
         :ok <- require_list(payload, "permissions") do
      :ok
    end
  end

  def validate(%{kind: :capability_revoked, payload: payload}) do
    require_binary(payload, "grantee")
  end

  defp require_binary(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a binary"}
    end
  end

  defp require_present(payload, key) do
    case Map.get(payload, key) do
      nil -> {:error, "missing required field: #{key}"}
      _ -> :ok
    end
  end

  defp require_list(payload, key) do
    case Map.get(payload, key) do
      value when is_list(value) -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a list"}
    end
  end
end

defmodule WorkersUnite.Schema.Proposal do
  @moduledoc """
  Validates payloads for proposal-related events.
  """

  @required_submission_fields ~w(intent_ref repo_id summary confidence affected_files artifact)

  @doc """
  Validates a proposal event's payload.

  All proposal kinds require `intent_ref`.

  - `:proposal_submitted` — also requires `commit_range` (map with `from` and `to`).
  - `:proposal_updated` — also requires `proposal_ref`.
  - `:proposal_withdrawn` — also requires `proposal_ref`.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(%{kind: atom(), payload: map()}) :: :ok | {:error, String.t()}
  def validate(%{kind: :proposal_submitted, payload: payload}) do
    with :ok <- require_fields(payload, @required_submission_fields),
         :ok <- require_binary(payload, "intent_ref"),
         :ok <- require_binary(payload, "repo_id"),
         :ok <- require_non_empty_string(payload, "summary"),
         :ok <- validate_confidence(payload),
         :ok <- validate_affected_files(payload),
         :ok <- validate_artifact(payload) do
      :ok
    end
  end

  def validate(%{kind: :proposal_updated, payload: payload}) do
    with :ok <- require_binary(payload, "intent_ref"),
         :ok <- require_binary(payload, "proposal_ref") do
      :ok
    end
  end

  def validate(%{kind: :proposal_withdrawn, payload: payload}) do
    with :ok <- require_binary(payload, "intent_ref"),
         :ok <- require_binary(payload, "proposal_ref") do
      :ok
    end
  end

  defp validate_artifact(payload) do
    case Map.get(payload, "artifact") do
      %{"type" => "commit_range", "from" => from, "to" => to}
      when is_binary(from) and is_binary(to) ->
        :ok

      %{"type" => "branch", "name" => name, "head" => head}
      when is_binary(name) and is_binary(head) ->
        :ok

      %{"type" => "patch", "diff" => diff} = artifact when is_binary(diff) ->
        case Map.get(artifact, "base") do
          nil -> :ok
          base when is_binary(base) -> :ok
          _ -> {:error, "patch artifact base must be a binary or null"}
        end

      nil ->
        {:error, "missing required field: artifact"}

      _ ->
        {:error, "artifact must be commit_range, branch, or patch"}
    end
  end

  defp validate_confidence(payload) do
    case Map.get(payload, "confidence") do
      value when is_number(value) and value >= 0.0 and value <= 1.0 -> :ok
      value when is_number(value) -> {:error, "confidence must be between 0.0 and 1.0"}
      _ -> {:error, "confidence must be a number"}
    end
  end

  defp validate_affected_files(payload) do
    case Map.get(payload, "affected_files") do
      files when is_list(files) ->
        if Enum.all?(files, &is_binary/1),
          do: :ok,
          else: {:error, "affected_files must be a list of strings"}

      _ ->
        {:error, "affected_files must be a list of strings"}
    end
  end

  defp require_fields(payload, keys) do
    missing = Enum.reject(keys, &Map.has_key?(payload, &1))

    case missing do
      [] -> :ok
      _ -> {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp require_binary(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a binary"}
    end
  end

  defp require_non_empty_string(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) and byte_size(value) > 0 -> :ok
      nil -> {:error, "missing required field: #{key}"}
      _ -> {:error, "#{key} must be a non-empty string"}
    end
  end
end

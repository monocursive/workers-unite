defmodule WorkersUnite.EventRecord do
  @moduledoc """
  Ecto schema for persisting events to Postgres.
  Handles conversion between domain Event structs and database records.
  """

  use Ecto.Schema

  @primary_key {:id, :binary, autogenerate: false}
  schema "events" do
    field :kind, :string
    field :author, :binary
    field :payload, :map, default: %{}
    field :timestamp, :integer
    field :signature, :binary
    field :references, {:array, :map}, default: []
    field :scope_type, :string
    field :scope_id, :binary

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Convert a domain Event struct to an EventRecord changeset."
  def to_record(%WorkersUnite.Event{} = event) do
    {scope_type, scope_id} = parse_scope(event.scope)

    refs =
      Enum.map(event.references, fn
        {type, id} -> %{"type" => to_string(type), "id" => id}
        %{"type" => _, "id" => _} = ref -> ref
        ref when is_map(ref) -> ref
      end)

    %__MODULE__{
      id: event.id,
      kind: to_string(event.kind),
      author: event.author,
      payload: stringify_keys(event.payload),
      timestamp: event.timestamp,
      signature: event.signature,
      references: refs,
      scope_type: scope_type,
      scope_id: scope_id
    }
  end

  @doc "Convert an EventRecord back to a domain Event struct."
  def from_record(%__MODULE__{} = record) do
    refs =
      Enum.map(record.references, fn
        %{"type" => type, "id" => id} -> {safe_to_atom(type), id}
        other -> other
      end)

    scope =
      if record.scope_type && record.scope_id do
        {safe_to_atom(record.scope_type), record.scope_id}
      end

    %WorkersUnite.Event{
      id: record.id,
      kind: safe_to_atom(record.kind),
      author: record.author,
      payload: record.payload,
      timestamp: record.timestamp,
      signature: record.signature,
      references: refs,
      scope: scope
    }
  end

  @known_atoms ~w(
    agent_joined agent_left agent_provenance
    intent_published intent_claimed intent_decomposed intent_contested
    intent_withdrawn intent_updated intent_cancelled
    proposal_submitted proposal_revised proposal_updated proposal_withdrawn
    validation_requested validation_result
    vote_cast consensus_reached consensus_failed
    merge_executed merge_rejected
    capability_granted capability_revoked
    repo_created repo_ref_updated
    session_completed session_failed
    comment_added annotation_added
    repo intent proposal agent
  )a

  defp safe_to_atom(str) when is_binary(str) do
    Enum.find(@known_atoms, fn atom -> Atom.to_string(atom) == str end) ||
      raise ArgumentError, "unknown atom from DB: #{inspect(str)}"
  end

  defp parse_scope(nil), do: {nil, nil}
  defp parse_scope({type, id}), do: {to_string(type), id}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end

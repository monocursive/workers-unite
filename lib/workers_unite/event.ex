defmodule WorkersUnite.Event do
  @moduledoc """
  Immutable, cryptographically signed events that form the WorkersUnite event log.
  Each event is content-addressed (id = SHA-256 of canonical bytes) and
  authenticated via Ed25519 signature.
  """

  @valid_kinds [
    # Agent lifecycle
    :agent_joined,
    :agent_left,
    :agent_provenance,
    # Intent flow
    :intent_published,
    :intent_claimed,
    :intent_decomposed,
    :intent_contested,
    :intent_withdrawn,
    :intent_updated,
    :intent_cancelled,
    # Proposal flow
    :proposal_submitted,
    :proposal_revised,
    :proposal_updated,
    :proposal_withdrawn,
    # Validation
    :validation_requested,
    :validation_result,
    # Consensus
    :vote_cast,
    :consensus_reached,
    :consensus_failed,
    # Execution
    :merge_executed,
    :merge_rejected,
    # Session lifecycle
    :session_completed,
    :session_failed,
    # Capabilities
    :capability_granted,
    :capability_revoked,
    # Repository
    :repo_created,
    :repo_ref_updated,
    # Annotations
    :comment_added,
    :annotation_added
  ]

  @enforce_keys [:id, :kind, :author, :payload, :timestamp, :signature]
  defstruct [
    :id,
    :kind,
    :author,
    :payload,
    :timestamp,
    :signature,
    references: [],
    scope: nil
  ]

  @type t :: %__MODULE__{
          id: binary(),
          kind: atom(),
          author: binary(),
          payload: term(),
          timestamp: integer(),
          signature: binary(),
          references: [binary()],
          scope: term()
        }

  @doc """
  Returns the list of all valid event kinds.
  """
  def valid_kinds, do: @valid_kinds

  @doc """
  Returns the hex-encoded event ID (lowercase).
  Use this as the canonical reference format for all cross-event links.
  """
  def ref(%__MODULE__{id: id}), do: Base.encode16(id, case: :lower)

  @doc """
  Creates a new signed event.

  Builds a canonical representation, hashes it for the id, and signs the
  canonical bytes with the keypair's secret key.

  Payload keys are normalized to strings for consistency across Postgres roundtrips.
  """
  def new(kind, keypair, payload, opts \\ []) do
    if kind not in @valid_kinds do
      {:error, "invalid event kind: #{inspect(kind)}"}
    else
      canonical = %{
        kind: kind,
        author: keypair.public,
        payload: stringify_keys(payload),
        timestamp: opts[:timestamp] || System.os_time(:millisecond),
        references: opts[:references] || [],
        scope: opts[:scope]
      }

      bytes = canonical_bytes(canonical)
      id = :crypto.hash(:sha256, bytes)
      signature = WorkersUnite.Identity.sign(bytes, keypair.secret)

      {:ok,
       %__MODULE__{
         id: id,
         kind: canonical.kind,
         author: canonical.author,
         payload: canonical.payload,
         timestamp: canonical.timestamp,
         signature: signature,
         references: canonical.references,
         scope: canonical.scope
       }}
    end
  end

  @doc """
  Verifies an event's integrity and authenticity.

  Rebuilds the canonical bytes from the event fields, checks that the id
  matches the SHA-256 hash of those bytes, and verifies the Ed25519 signature.

  Returns `{:ok, event}` or `{:error, reason}`.
  """
  def verify(%__MODULE__{} = event) do
    bytes = canonical_bytes(event)
    expected_id = :crypto.hash(:sha256, bytes)

    cond do
      event.id != expected_id ->
        {:error, "id mismatch"}

      not WorkersUnite.Identity.verify(bytes, event.signature, event.author) ->
        {:error, "invalid signature"}

      true ->
        {:ok, event}
    end
  end

  defp canonical_bytes(%__MODULE__{} = event) do
    %{
      kind: event.kind,
      author: event.author,
      payload: event.payload,
      timestamp: event.timestamp,
      references: event.references,
      scope: event.scope
    }
    |> canonical_bytes()
  end

  defp canonical_bytes(%{} = map) do
    :erlang.term_to_binary(map, [:deterministic])
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end

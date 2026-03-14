defmodule WorkersUnite.Schema do
  @moduledoc """
  Validates event payloads by kind.

  Routes each event to the appropriate sub-module for payload validation.
  Events whose kinds have no payload constraints pass through with `:ok`.
  """

  alias WorkersUnite.Schema.{Intent, Proposal, Vote, Capability}

  @intent_kinds [
    :intent_published,
    :intent_claimed,
    :intent_decomposed,
    :intent_contested,
    :intent_withdrawn,
    :intent_updated,
    :intent_cancelled
  ]
  @proposal_kinds [:proposal_submitted, :proposal_revised, :proposal_updated, :proposal_withdrawn]
  @passthrough_kinds [
    :agent_joined,
    :agent_left,
    :agent_provenance,
    :repo_created,
    :repo_ref_updated,
    :merge_executed,
    :merge_rejected,
    :session_completed,
    :session_failed,
    :validation_requested,
    :validation_result,
    :consensus_failed,
    :comment_added,
    :annotation_added
  ]

  @doc """
  Validates an event's payload against the schema for its kind.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(%{kind: atom(), payload: term()}) :: :ok | {:error, String.t()}
  def validate(%{kind: kind} = event) when kind in @intent_kinds do
    Intent.validate(event)
  end

  def validate(%{kind: kind} = event) when kind in @proposal_kinds do
    Proposal.validate(event)
  end

  def validate(%{kind: :vote_cast} = event) do
    Vote.validate(event)
  end

  def validate(%{kind: kind} = event) when kind in [:capability_granted, :capability_revoked] do
    Capability.validate(event)
  end

  def validate(%{kind: :consensus_reached}) do
    :ok
  end

  def validate(%{kind: kind}) when kind in @passthrough_kinds do
    :ok
  end

  def validate(%{kind: _kind}) do
    {:error, "unknown event kind"}
  end
end

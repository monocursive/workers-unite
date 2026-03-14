defmodule WorkersUniteWeb.OperatorMCP.Tools.CastVote do
  @moduledoc """
  Casts an operator vote on a proposal using the node's Vault identity.
  The operator's user_id is recorded in the payload for audit purposes.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Event, EventStore, Identity}
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @valid_verdicts ["accept", "reject", "abstain"]

  @impl true
  def definition do
    %{
      "name" => "wu_cast_vote",
      "description" =>
        "Casts an operator vote on a proposal. The vote is signed by the node's " <>
          "Vault identity with the operator's user ID recorded for audit.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["proposal_ref", "verdict", "confidence"],
        "properties" => %{
          "proposal_ref" => %{
            "type" => "string",
            "description" => "Hex-encoded event ref of the proposal to vote on"
          },
          "verdict" => %{
            "type" => "string",
            "enum" => @valid_verdicts,
            "description" => "Vote verdict: accept, reject, or abstain"
          },
          "confidence" => %{
            "type" => "number",
            "description" => "Confidence level between 0.0 and 1.0"
          },
          "rationale" => %{
            "type" => "string",
            "description" => "Explanation for the vote"
          }
        }
      }
    }
  end

  @impl true
  def call(
        %{
          "proposal_ref" => proposal_ref,
          "verdict" => verdict,
          "confidence" => confidence
        } = params,
        context
      )
      when verdict in @valid_verdicts and is_number(confidence) and confidence >= 0 and
             confidence <= 1 do
    keypair = Identity.Vault.keypair()

    with {:ok, proposal} <- Helpers.fetch_proposal(proposal_ref),
         :ok <- check_duplicate_vote(proposal_ref, keypair.public) do
      payload =
        %{
          "proposal_ref" => proposal_ref,
          "verdict" => verdict,
          "confidence" => confidence,
          "operator_user_id" => context.user_id
        }
        |> maybe_put("rationale", params["rationale"])

      opts = [references: [{:proposal, proposal_ref}]]
      opts = if proposal.scope, do: Keyword.put(opts, :scope, proposal.scope), else: opts

      case Event.new(:vote_cast, keypair, payload, opts) do
        {:ok, event} ->
          case EventStore.append(event) do
            {:ok, stored} ->
              {:ok,
               %{
                 event_ref: Event.ref(stored),
                 proposal_ref: proposal_ref,
                 verdict: verdict,
                 confidence: confidence
               }}

            {:error, _} = error ->
              error
          end

        {:error, _} = error ->
          error
      end
    end
  end

  def call(%{"verdict" => verdict}, _context) when verdict not in @valid_verdicts do
    {:error, {:invalid_verdict, "must be one of: #{Enum.join(@valid_verdicts, ", ")}"}}
  end

  def call(%{"confidence" => c}, _context) when not is_number(c) or c < 0 or c > 1 do
    {:error, {:invalid_confidence, "must be a number between 0.0 and 1.0"}}
  end

  def call(_params, _context), do: {:error, :invalid_params}

  # Operator events are signed with node Vault keypair. In federation, these are
  # attributable to the node, not individual operators. Per-operator Ed25519 keys
  # are a future enhancement.

  defp check_duplicate_vote(proposal_ref, author) do
    existing =
      EventStore.by_kind(:vote_cast)
      |> Enum.find(fn e ->
        e.payload["proposal_ref"] == proposal_ref and e.author == author
      end)

    if existing do
      {:error, "vote already cast on this proposal by this author"}
    else
      :ok
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

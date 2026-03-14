defmodule WorkersUniteWeb.OperatorMCP.Tools.InspectConsensus do
  @moduledoc """
  Returns the consensus status for a proposal, including all votes cast
  and the current evaluation outcome.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Identity, Repository, Consensus.Engine}
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_inspect_consensus",
      "description" =>
        "Returns the consensus status for a specific proposal. Shows all votes cast " <>
          "(with author fingerprint, verdict, and confidence) and the current consensus " <>
          "evaluation result.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["proposal_ref"],
        "properties" => %{
          "proposal_ref" => %{
            "type" => "string",
            "description" => "The event reference of the proposal to inspect"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"proposal_ref" => proposal_ref}, _context) do
    votes =
      Helpers.proposal_votes(proposal_ref)
      |> Enum.map(fn event ->
        %{
          author_fingerprint: Identity.fingerprint(event.author),
          verdict: event.payload["verdict"],
          confidence: event.payload["confidence"],
          timestamp: event.timestamp
        }
      end)

    consensus_evaluation =
      case Engine.evaluate(proposal_ref) do
        {:ok, outcome} -> to_string(outcome)
        {:error, reason} -> "error: #{inspect(reason)}"
      end

    policy = resolve_policy(proposal_ref)

    {:ok,
     %{
       proposal_ref: proposal_ref,
       votes: votes,
       vote_count: length(votes),
       consensus_status: consensus_evaluation,
       policy: policy
     }}
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp resolve_policy(proposal_ref) do
    case Helpers.fetch_proposal(proposal_ref) do
      {:ok, %{scope: {:repo, repo_id}}} ->
        try do
          state = Repository.get_state(repo_id)
          state.policy || Application.get_env(:workers_unite, :default_consensus_policy)
        catch
          :exit, _ -> Application.get_env(:workers_unite, :default_consensus_policy)
        end

      _ ->
        Application.get_env(:workers_unite, :default_consensus_policy)
    end
  end
end

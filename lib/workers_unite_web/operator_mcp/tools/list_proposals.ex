defmodule WorkersUniteWeb.OperatorMCP.Tools.ListProposals do
  @moduledoc """
  Lists proposals with optional repository filter, including vote counts
  and consensus status for each.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Event, EventStore, Identity}
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_list_proposals",
      "description" =>
        "Lists proposals (agent-submitted code changes). Optionally filter by repo_id. " <>
          "Each proposal includes its vote count and current consensus status.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "repo_id" => %{
            "type" => "string",
            "description" =>
              "Hex-encoded repository ID. If omitted, lists proposals across all repos."
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of proposals to return (default 100)"
          }
        }
      }
    }
  end

  @max_limit 100

  @impl true
  def call(params, _context) do
    limit = parse_limit(params)

    proposals =
      EventStore.by_kind(:proposal_submitted)
      |> maybe_filter_by_repo(params["repo_id"])
      |> Enum.map(fn event ->
        proposal_ref = Event.ref(event)
        votes = Helpers.proposal_votes(proposal_ref)

        repo_id =
          case event.scope do
            {:repo, id} -> Base.encode16(id, case: :lower)
            _ -> nil
          end

        consensus_status = evaluate_consensus_status(proposal_ref)

        %{
          ref: proposal_ref,
          intent_ref: event.payload["intent_ref"],
          author_fingerprint: Identity.fingerprint(event.author),
          timestamp: event.timestamp,
          repo_id: repo_id,
          artifact: event.payload["artifact"],
          vote_count: length(votes),
          consensus_status: consensus_status
        }
      end)
      |> Enum.take(limit)

    {:ok, proposals}
  end

  defp parse_limit(%{"limit" => l}) when is_integer(l) and l > 0, do: min(l, @max_limit)
  defp parse_limit(_), do: @max_limit

  defp maybe_filter_by_repo(events, nil), do: events

  defp maybe_filter_by_repo(events, repo_id) do
    Enum.filter(events, fn event ->
      case event.scope do
        {:repo, id} -> Base.encode16(id, case: :lower) == String.downcase(repo_id)
        _ -> false
      end
    end)
  end

  defp evaluate_consensus_status(proposal_ref) do
    consensus_events = EventStore.by_kind(:consensus_reached)

    case Enum.find(consensus_events, fn e -> e.payload["proposal_ref"] == proposal_ref end) do
      nil -> "pending"
      event -> event.payload["outcome"] || "unknown"
    end
  end
end

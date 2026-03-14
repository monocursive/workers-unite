defmodule WorkersUniteWeb.OperatorMCP.Tools.QueryEvents do
  @moduledoc """
  Queries the append-only event log with optional filters for kind, scope,
  author, and time range.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.EventStore
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @max_limit 100

  @impl true
  def definition do
    %{
      "name" => "wu_query_events",
      "description" =>
        "Queries the event log with optional filters. Use this to inspect the history " <>
          "of what has happened on this WorkersUnite instance — agent joins, intents, " <>
          "proposals, votes, consensus outcomes, merges, and more.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "kind" => %{
            "type" => "string",
            "description" =>
              "Filter by event kind (e.g. agent_joined, intent_published, proposal_submitted, vote_cast, consensus_reached)"
          },
          "scope_repo_id" => %{
            "type" => "string",
            "description" => "Filter by repository scope (hex-encoded repo ID)"
          },
          "author" => %{
            "type" => "string",
            "description" => "Filter by author public key (hex-encoded)"
          },
          "since" => %{
            "type" => "integer",
            "description" => "Only return events after this Unix timestamp in milliseconds"
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of events to return (default 50, max 100)"
          }
        }
      }
    }
  end

  @impl true
  def call(params, _context) do
    events =
      base_events(params)
      |> filter_author(params["author"])
      |> filter_since(params["since"])
      |> Enum.take(limit(params["limit"]))
      |> Enum.map(&Helpers.summarize_event/1)

    {:ok, events}
  end

  defp base_events(%{"kind" => kind}) when is_binary(kind) do
    try do
      EventStore.by_kind(String.to_existing_atom(kind))
    rescue
      ArgumentError -> []
    end
  end

  defp base_events(%{"scope_repo_id" => repo_id}) when is_binary(repo_id) do
    case Base.decode16(repo_id, case: :mixed) do
      {:ok, binary} -> EventStore.by_scope({:repo, binary})
      :error -> []
    end
  end

  defp base_events(_params), do: EventStore.stream()

  defp filter_author(events, nil), do: events

  defp filter_author(events, author) do
    Enum.filter(events, fn event ->
      Base.encode16(event.author, case: :lower) == String.downcase(author)
    end)
  end

  defp filter_since(events, nil), do: events
  defp filter_since(events, since), do: Enum.filter(events, &(&1.timestamp >= since))

  defp limit(value) when is_integer(value), do: min(value, @max_limit)
  defp limit(_value), do: 50
end

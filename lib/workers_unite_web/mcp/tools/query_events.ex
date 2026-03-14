defmodule WorkersUniteWeb.MCP.Tools.QueryEvents do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.EventStore
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @max_limit 100

  @impl true
  def definition do
    %{
      "name" => "workers_unite_query_events",
      "description" => "Queries the event log with simple filters.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"type" => "string"},
          "scope_repo_id" => %{"type" => "string"},
          "author" => %{"type" => "string"},
          "since" => %{"type" => "integer"},
          "limit" => %{"type" => "integer"}
        }
      }
    }
  end

  @impl true
  def call(params, _context) do
    events =
      EventStore.stream()
      |> filter_kind(params["kind"])
      |> filter_scope(params["scope_repo_id"])
      |> filter_author(params["author"])
      |> filter_since(params["since"])
      |> Enum.take(limit(params["limit"]))
      |> Enum.map(&Helpers.summarize_event/1)

    {:ok, events}
  end

  defp filter_kind(events, nil), do: events
  defp filter_kind(events, kind), do: Enum.filter(events, &(to_string(&1.kind) == kind))

  defp filter_scope(events, nil), do: events

  defp filter_scope(events, repo_id),
    do: Enum.filter(events, &match?({:repo, ^repo_id}, scope_ref(&1)))

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

  defp scope_ref(event) do
    case event.scope do
      {:repo, repo_id} -> {:repo, Base.encode16(repo_id, case: :lower)}
      other -> other
    end
  end
end

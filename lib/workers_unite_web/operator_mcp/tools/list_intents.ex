defmodule WorkersUniteWeb.OperatorMCP.Tools.ListIntents do
  @moduledoc """
  Lists intents for a specific repository or across all repos.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Event, EventStore, Identity}
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_list_intents",
      "description" =>
        "Lists intents (work items for agents). When repo_id is provided, returns " <>
          "active intents for that repository. When omitted, returns all intent_published " <>
          "events across all repos.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "repo_id" => %{
            "type" => "string",
            "description" =>
              "Hex-encoded repository ID. If omitted, lists intents across all repos."
          },
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of intents to return (default 100)"
          }
        }
      }
    }
  end

  @max_limit 100

  @impl true
  def call(%{"repo_id" => repo_id} = params, _context) when is_binary(repo_id) do
    limit = parse_limit(params)

    with {:ok, state} <- Helpers.fetch_repo(repo_id) do
      intents =
        state.active_intents
        |> Enum.map(fn {ref, event} ->
          %{
            ref: ref,
            title: event.payload["title"],
            description: event.payload["description"],
            priority: event.payload["priority"],
            tags: event.payload["tags"] || [],
            author_fingerprint: Identity.fingerprint(event.author),
            timestamp: event.timestamp,
            repo_id: repo_id
          }
        end)
        |> Enum.take(limit)

      {:ok, intents}
    end
  end

  def call(params, _context) do
    limit = parse_limit(params)

    intents =
      EventStore.by_kind(:intent_published)
      |> Enum.map(fn event ->
        repo_id =
          case event.scope do
            {:repo, id} -> Base.encode16(id, case: :lower)
            _ -> nil
          end

        %{
          ref: Event.ref(event),
          title: event.payload["title"],
          description: event.payload["description"],
          priority: event.payload["priority"],
          tags: event.payload["tags"] || [],
          author_fingerprint: Identity.fingerprint(event.author),
          timestamp: event.timestamp,
          repo_id: repo_id
        }
      end)
      |> Enum.take(limit)

    {:ok, intents}
  end

  defp parse_limit(%{"limit" => l}) when is_integer(l) and l > 0, do: min(l, @max_limit)
  defp parse_limit(_), do: @max_limit
end

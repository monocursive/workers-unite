defmodule WorkersUniteWeb.OperatorMCP.Tools.ListRepos do
  @moduledoc """
  Lists all repositories registered on this WorkersUnite instance.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Repository

  @impl true
  def definition do
    %{
      "name" => "wu_list_repos",
      "description" =>
        "Lists all repositories on this WorkersUnite instance. Returns each repo's " <>
          "hex ID, name, path, and counts of active intents, proposals, and participating agents.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "limit" => %{
            "type" => "integer",
            "description" => "Maximum number of repos to return (default 100)"
          }
        }
      }
    }
  end

  @impl true
  def call(params, _context) do
    limit = parse_limit(params)

    repos =
      Repository.list_local()
      |> Enum.map(fn %{repo_id: repo_id} ->
        state = Repository.get_state(repo_id)

        %{
          repo_id: Base.encode16(repo_id, case: :lower),
          name: state.name,
          active_intents_count: map_size(state.active_intents),
          active_proposals_count: map_size(state.active_proposals),
          agents_count: MapSet.size(state.agents)
        }
      end)
      |> Enum.take(limit)

    {:ok, repos}
  catch
    :exit, _reason -> {:ok, []}
  end

  defp parse_limit(%{"limit" => l}) when is_integer(l) and l > 0, do: min(l, 100)
  defp parse_limit(_), do: 100
end

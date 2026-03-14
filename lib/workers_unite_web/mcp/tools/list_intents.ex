defmodule WorkersUniteWeb.MCP.Tools.ListIntents do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Repository
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_list_intents",
      "description" => "Lists open, unclaimed intents for a repository.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{"repo_id" => %{"type" => "string"}}
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id}, _context) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id) do
      intents =
        Repository.list_open_intents(repo_id_binary)
        |> Enum.map(fn event ->
          %{
            ref: WorkersUnite.Event.ref(event),
            title: event.payload["title"],
            description: event.payload["description"],
            priority: event.payload["priority"],
            tags: event.payload["tags"] || []
          }
        end)

      {:ok, intents}
    end
  catch
    :exit, _reason -> {:error, :repo_not_found}
  end

  def call(_params, _context), do: {:error, :invalid_params}
end

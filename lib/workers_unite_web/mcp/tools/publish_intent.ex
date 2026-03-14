defmodule WorkersUniteWeb.MCP.Tools.PublishIntent do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_publish_intent",
      "description" => "Publishes a new intent in a repository.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id", "title"],
        "properties" => %{
          "repo_id" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "priority" => %{"type" => "number"},
          "tags" => %{"type" => "array"}
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id} = params, %{agent_id: agent_id}) do
    repo_id_binary = Helpers.decode_repo_id(repo_id)

    payload =
      params
      |> Map.drop(["repo_id"])

    with {:ok, event_ref} <- Agent.publish_intent(agent_id, repo_id_binary, payload) do
      {:ok, %{event_ref: event_ref}}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}
end

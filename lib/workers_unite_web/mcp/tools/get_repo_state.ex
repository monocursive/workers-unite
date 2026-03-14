defmodule WorkersUniteWeb.MCP.Tools.GetRepoState do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_get_repo_state",
      "description" => "Returns repository metadata and projection state.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{"repo_id" => %{"type" => "string"}}
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id}, _context) do
    with {:ok, repo} <- Helpers.fetch_repo(repo_id) do
      {:ok,
       %{
         name: repo.name,
         active_intents_count: map_size(repo.active_intents),
         active_proposals_count: map_size(repo.active_proposals),
         agents_count: MapSet.size(repo.agents),
         policy: repo.policy
       }}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}
end

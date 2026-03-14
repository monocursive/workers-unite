defmodule WorkersUniteWeb.MCP.Tools.ClaimIntent do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_claim_intent",
      "description" => "Claims an open intent in a repository.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id", "intent_ref"],
        "properties" => %{
          "repo_id" => %{"type" => "string"},
          "intent_ref" => %{"type" => "string"}
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id, "intent_ref" => intent_ref}, %{agent_id: agent_id}) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id),
         {:ok, event_ref} <-
           Agent.claim_intent(agent_id, repo_id_binary, intent_ref, {:repo, repo_id_binary}) do
      {:ok, %{event_ref: event_ref}}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}
end

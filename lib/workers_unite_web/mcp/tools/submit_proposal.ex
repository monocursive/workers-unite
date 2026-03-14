defmodule WorkersUniteWeb.MCP.Tools.SubmitProposal do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_submit_proposal",
      "description" => "Submits a proposal with a reproducible artifact.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [
          "repo_id",
          "intent_ref",
          "summary",
          "confidence",
          "affected_files",
          "artifact"
        ],
        "properties" => %{
          "repo_id" => %{"type" => "string"},
          "intent_ref" => %{"type" => "string"},
          "summary" => %{"type" => "string"},
          "confidence" => %{"type" => "number"},
          "affected_files" => %{"type" => "array"},
          "artifact" => %{"type" => "object"}
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id} = params, %{agent_id: agent_id}) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id) do
      payload = Map.put(params, "repo_id", Base.encode16(repo_id_binary, case: :lower))

      with {:ok, event_ref} <- Agent.submit_proposal(agent_id, payload, {:repo, repo_id_binary}) do
        {:ok, %{event_ref: event_ref}}
      end
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}
end

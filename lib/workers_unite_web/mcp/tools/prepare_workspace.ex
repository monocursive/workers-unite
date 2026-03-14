defmodule WorkersUniteWeb.MCP.Tools.PrepareWorkspace do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUnite.Agent.Workspace
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_prepare_workspace",
      "description" => "Prepares a task checkout and branch for the current coder session.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{
          "repo_id" => %{"type" => "string"}
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id}, %{agent_id: agent_id, working_dir: working_dir}) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id),
         {:ok, task} <- active_intent_task(agent_id, repo_id_binary),
         {:ok, checkout} <-
           Workspace.prepare_task_checkout(working_dir, repo_id_binary, agent_id, task.ref) do
      {:ok,
       %{
         repo_path: checkout.repo_path,
         branch_name: checkout.branch_name,
         base_branch: checkout.base_branch,
         base_sha: checkout.base_sha,
         head_sha: checkout.head_sha,
         intent_ref: task.ref
       }}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp active_intent_task(agent_id, repo_id) do
    case Agent.inspect_state(agent_id).current_task do
      %{kind: :intent, ref: ref, repo_id: ^repo_id} = task -> {:ok, %{task | ref: ref}}
      %{repo_id: ^repo_id} -> {:error, :task_must_be_claimed_intent}
      %{repo_id: _other_repo_id} -> {:error, :repo_mismatch}
      nil -> {:error, :no_active_task}
    end
  end
end

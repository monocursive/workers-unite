defmodule WorkersUniteWeb.MCP.Tools.PublishArtifact do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent
  alias WorkersUnite.Agent.Workspace
  alias WorkersUnite.Git
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_publish_artifact",
      "description" => "Commits and pushes task branch changes, returning a proposal artifact.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{
          "repo_id" => %{"type" => "string"},
          "commit_message" => %{"type" => "string"}
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id} = params, %{agent_id: agent_id, working_dir: working_dir}) do
    repo_id_binary = Helpers.decode_repo_id(repo_id)

    with {:ok, task} <- active_intent_task(agent_id, repo_id_binary),
         {:ok, checkout} <-
           Workspace.checkout_task_branch(working_dir, repo_id_binary, agent_id, task.ref),
         {:ok, changed_files} <- Git.changed_files(checkout.repo_path),
         {:ok, _commit_result} <-
           Git.commit_all(checkout.repo_path, commit_message(params["commit_message"], task.ref)),
         :ok <- Git.push_branch(checkout.repo_path, checkout.branch_name),
         {:ok, head_sha} <- Git.rev_parse(checkout.repo_path, "HEAD") do
      {:ok,
       %{
         artifact: %{
           type: "branch",
           name: checkout.branch_name,
           head: head_sha
         },
         affected_files: changed_files,
         branch_name: checkout.branch_name,
         head_sha: head_sha,
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

  defp commit_message(nil, intent_ref),
    do: "WorkersUnite changes for #{String.slice(intent_ref, 0, 12)}"

  defp commit_message(message, _intent_ref), do: message
end

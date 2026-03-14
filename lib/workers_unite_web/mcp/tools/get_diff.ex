defmodule WorkersUniteWeb.MCP.Tools.GetDiff do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.EventStore

  @impl true
  def definition do
    %{
      "name" => "workers_unite_get_diff",
      "description" => "Returns a diff derived from a proposal artifact.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["proposal_ref"],
        "properties" => %{"proposal_ref" => %{"type" => "string"}}
      }
    }
  end

  @impl true
  def call(%{"proposal_ref" => proposal_ref}, _context) do
    with {:ok, proposal} <- fetch_proposal(proposal_ref),
         {:ok, diff_payload} <- resolve_diff(proposal.payload) do
      {:ok,
       Map.merge(diff_payload, %{
         artifact: proposal.payload["artifact"],
         affected_files: proposal.payload["affected_files"] || []
       })}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp fetch_proposal(proposal_ref) do
    EventStore.by_kind(:proposal_submitted)
    |> Enum.find(&(WorkersUnite.Event.ref(&1) == proposal_ref))
    |> case do
      nil -> {:error, :proposal_not_found}
      proposal -> {:ok, proposal}
    end
  end

  defp resolve_diff(%{"artifact" => %{"type" => "patch", "diff" => diff}}) do
    {:ok, %{diff: diff, stats: nil}}
  end

  defp resolve_diff(%{
         "artifact" => %{"type" => "commit_range", "from" => from, "to" => to},
         "repo_id" => repo_id
       }) do
    run_git_diff(repo_id, ["diff", from, to, "--stat", "--patch"])
  end

  defp resolve_diff(%{"artifact" => %{"type" => "branch", "head" => head}, "repo_id" => repo_id}) do
    run_git_show(repo_id, ["show", "--stat", "--patch", head])
  end

  defp resolve_diff(_payload), do: {:error, :unsupported_artifact}

  defp run_git_diff(repo_id, args) do
    with {:ok, repo} <- WorkersUniteWeb.MCP.Tools.Helpers.fetch_repo(repo_id) do
      {output, code} = System.cmd("git", args, cd: repo.path, stderr_to_stdout: true)
      if code == 0, do: {:ok, %{diff: output, stats: output}}, else: {:error, :diff_unavailable}
    end
  end

  defp run_git_show(repo_id, args) do
    with {:ok, repo} <- WorkersUniteWeb.MCP.Tools.Helpers.fetch_repo(repo_id) do
      {output, code} = System.cmd("git", args, cd: repo.path, stderr_to_stdout: true)
      if code == 0, do: {:ok, %{diff: output, stats: output}}, else: {:error, :diff_unavailable}
    end
  end
end

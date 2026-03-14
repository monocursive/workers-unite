defmodule WorkersUniteWeb.OperatorMCP.Tools.GetProposalDiff do
  @moduledoc """
  Returns the diff for a proposal, resolved from its artifact (patch, commit
  range, or branch).
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_get_proposal_diff",
      "description" =>
        "Returns the diff for a proposal identified by its event reference. " <>
          "Resolves the diff from the proposal's artifact (patch text, commit range, " <>
          "or branch). Returns the diff text, stats, and affected files.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["proposal_ref"],
        "properties" => %{
          "proposal_ref" => %{
            "type" => "string",
            "description" => "The event reference of the proposal"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"proposal_ref" => proposal_ref}, _context) do
    with {:ok, proposal} <- Helpers.fetch_proposal(proposal_ref),
         {:ok, diff_payload} <- resolve_diff(proposal.payload) do
      {:ok,
       Map.merge(diff_payload, %{
         proposal_ref: proposal_ref,
         artifact: proposal.payload["artifact"],
         affected_files: proposal.payload["affected_files"] || []
       })}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp resolve_diff(%{"artifact" => %{"type" => "patch", "diff" => diff}}) do
    {:ok, %{diff: diff, stats: nil}}
  end

  defp resolve_diff(%{
         "artifact" => %{"type" => "commit_range", "from" => from, "to" => to},
         "repo_id" => repo_id
       }) do
    with :ok <- validate_git_ref(from),
         :ok <- validate_git_ref(to) do
      run_git_cmd(repo_id, ["diff", from, to, "--stat", "--patch"])
    end
  end

  defp resolve_diff(%{"artifact" => %{"type" => "branch", "head" => head}, "repo_id" => repo_id}) do
    with :ok <- validate_git_ref(head) do
      run_git_cmd(repo_id, ["show", "--stat", "--patch", head])
    end
  end

  defp resolve_diff(_payload), do: {:error, :unsupported_artifact}

  @git_ref_pattern ~r/^[a-zA-Z0-9._\-\/]{1,256}$/

  defp validate_git_ref(ref) when is_binary(ref) do
    if String.starts_with?(ref, "--") or not Regex.match?(@git_ref_pattern, ref) do
      {:error, :invalid_git_ref}
    else
      :ok
    end
  end

  defp validate_git_ref(_), do: {:error, :invalid_git_ref}

  defp run_git_cmd(repo_id, args) do
    with {:ok, repo} <- Helpers.fetch_repo(repo_id) do
      {output, code} = System.cmd("git", args, cd: repo.path, stderr_to_stdout: true)
      if code == 0, do: {:ok, %{diff: output, stats: output}}, else: {:error, :diff_unavailable}
    end
  end
end

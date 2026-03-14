defmodule WorkersUniteWeb.MCP.ToolRegistry do
  @moduledoc """
  Maps MCP tool names to handler modules and authorized agent kinds.
  """

  alias WorkersUniteWeb.MCP.Tools

  @tools %{
    "workers_unite_get_state" => {Tools.GetAgentState, [:coder, :reviewer, :orchestrator]},
    "workers_unite_query_events" => {Tools.QueryEvents, [:coder, :reviewer, :orchestrator]},
    "workers_unite_get_repo_state" => {Tools.GetRepoState, [:coder, :reviewer, :orchestrator]},
    "workers_unite_list_intents" => {Tools.ListIntents, [:coder, :orchestrator]},
    "workers_unite_claim_intent" => {Tools.ClaimIntent, [:coder]},
    "workers_unite_prepare_workspace" => {Tools.PrepareWorkspace, [:coder]},
    "workers_unite_publish_artifact" => {Tools.PublishArtifact, [:coder]},
    "workers_unite_submit_proposal" => {Tools.SubmitProposal, [:coder]},
    "workers_unite_run_tests" => {Tools.RunTests, [:coder]},
    "workers_unite_list_proposals" => {Tools.ListProposals, [:reviewer, :orchestrator]},
    "workers_unite_get_diff" => {Tools.GetDiff, [:reviewer]},
    "workers_unite_cast_vote" => {Tools.CastVote, [:reviewer]},
    "workers_unite_publish_comment" => {Tools.PublishComment, [:reviewer]},
    "workers_unite_publish_intent" => {Tools.PublishIntent, [:orchestrator]},
    "workers_unite_list_agents" => {Tools.ListAgents, [:orchestrator]},
    "workers_unite_get_consensus" => {Tools.GetConsensus, [:orchestrator]}
  }

  def list_for_kind(kind) do
    @tools
    |> Enum.filter(fn {_name, {_module, allowed_kinds}} -> kind in allowed_kinds end)
    |> Enum.map(fn {_name, {module, _allowed_kinds}} -> module.definition() end)
  end

  def dispatch(name, arguments, %{kind: kind} = context) do
    case Map.get(@tools, name) do
      {module, allowed_kinds} ->
        if kind in allowed_kinds,
          do: module.call(arguments, context),
          else: {:error, :unauthorized}

      nil ->
        {:error, :tool_not_found}
    end
  end
end

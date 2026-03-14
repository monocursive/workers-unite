defmodule WorkersUniteWeb.OperatorMCP.ToolRegistry do
  @moduledoc """
  Maps operator MCP tool names to handler modules with scope-based authorization.

  Each tool declares the scopes required to invoke it. A token is authorized
  if it carries at least one of the required scopes.
  """

  alias WorkersUniteWeb.OperatorMCP.Tools

  @tools %{
    # Observe tools
    "wu_list_agents" => {Tools.ListAgents, ["observe"]},
    "wu_inspect_agent" => {Tools.InspectAgent, ["observe"]},
    "wu_list_repos" => {Tools.ListRepos, ["observe"]},
    "wu_inspect_repo" => {Tools.InspectRepo, ["observe"]},
    "wu_query_events" => {Tools.QueryEvents, ["observe"]},
    "wu_list_intents" => {Tools.ListIntents, ["observe"]},
    "wu_list_proposals" => {Tools.ListProposals, ["observe"]},
    "wu_inspect_consensus" => {Tools.InspectConsensus, ["observe"]},
    "wu_get_proposal_diff" => {Tools.GetProposalDiff, ["observe"]},
    "wu_list_sessions" => {Tools.ListSessions, ["observe"]},
    # Control tools
    "wu_publish_intent" => {Tools.PublishIntent, ["control"]},
    "wu_claim_intent" => {Tools.ClaimIntent, ["control"]},
    "wu_dispatch_work" => {Tools.DispatchWork, ["control"]},
    "wu_publish_comment" => {Tools.PublishComment, ["control"]},
    "wu_cast_vote" => {Tools.CastVote, ["control"]},
    "wu_cancel_session" => {Tools.CancelSession, ["control"]}
  }

  @doc """
  Returns tool definitions for all tools whose required scopes intersect
  with the given token scopes.
  """
  def list_for_scopes(scopes) do
    @tools
    |> Enum.filter(fn {_name, {_module, required_scopes}} ->
      Enum.any?(required_scopes, &(&1 in scopes))
    end)
    |> Enum.map(fn {_name, {module, _required_scopes}} -> module.definition() end)
  end

  @doc """
  Looks up a tool by name, checks that the context's scopes authorize it,
  and delegates to the handler module.

  Returns `{:ok, result}`, `{:error, :tool_not_found}`,
  `{:error, :unauthorized}`, or `{:error, reason}`.
  """
  def dispatch(name, arguments, %{scopes: scopes} = context) do
    case Map.get(@tools, name) do
      {module, required_scopes} ->
        if Enum.any?(required_scopes, &(&1 in scopes)) do
          module.call(arguments, context)
        else
          {:error, :unauthorized}
        end

      nil ->
        {:error, :tool_not_found}
    end
  end
end

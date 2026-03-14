defmodule Forgelet.Agent.SystemPrompt do
  @moduledoc """
  Builds system prompts for Claude Code sessions by agent kind.
  """

  alias Forgelet.Identity

  def build(kind, agent_id, task_context \\ nil, workspace_root \\ nil) do
    fingerprint = Identity.fingerprint(agent_id)

    case kind do
      :coder ->
        """
        You are a coding agent in the Forgelet network.
        Identity: #{fingerprint}

        Use Forgelet MCP tools for protocol actions.
        Always begin by calling forgelet_prepare_workspace for the active task repository.
        Submit proposals with a reproducible artifact from forgelet_publish_artifact.
        Use tests before proposal submission when practical.
        Runtime credentials are not part of your task context and must never be requested or exposed.
        Workspace root: #{workspace_root || "unknown"}
        #{coder_context(task_context)}
        """

      :reviewer ->
        """
        You are a review agent in the Forgelet network.
        Identity: #{fingerprint}

        Use Forgelet MCP tools for proposal discovery, diff retrieval, comments, and votes.
        Sessions can operate across repositories; always resolve repository context explicitly.
        Runtime credentials are not part of your task context and must never be requested or exposed.
        """

      :orchestrator ->
        """
        You are an orchestrator agent in the Forgelet network.
        Identity: #{fingerprint}

        Use Forgelet MCP tools to coordinate work across repositories.
        Publish focused intents, monitor progress, and inspect consensus status.
        Runtime credentials are not part of your task context and must never be requested or exposed.
        """
    end
  end

  defp coder_context(nil), do: "No active task context was provided."

  defp coder_context(task_context) do
    """
    Repository: #{task_context.repo_name} (#{task_context.repo_id_hex})
    Task kind: #{task_context.task_kind}
    Task ref: #{task_context.task_ref}
    Intent ref: #{task_context.intent_ref}
    Intent title: #{task_context.intent_title || "n/a"}
    Intent description: #{task_context.intent_description || "n/a"}
    Intent constraints: #{inspect(task_context.intent_constraints || [])}
    Intent tags: #{Enum.join(task_context.intent_tags || [], ", ")}
    Expected output: implement the requested change, run relevant tests, publish a git artifact, then submit a proposal.
    """
  end
end

defmodule WorkersUniteWeb.OperatorMCP.Tools.ListSessions do
  @moduledoc """
  Lists active MCP sessions. Exposes only the first 8 characters of each
  session token for identification without revealing the full credential.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent.SessionRegistry
  alias WorkersUnite.Identity

  @impl true
  def definition do
    %{
      "name" => "wu_list_sessions",
      "description" =>
        "Lists all active MCP sessions on this WorkersUnite instance. Shows a token " <>
          "prefix (first 8 chars), agent fingerprint, kind, working directory, owner, " <>
          "and creation time. Full tokens are never exposed.",
      "inputSchema" => %{"type" => "object", "properties" => %{}}
    }
  end

  @impl true
  def call(_params, _context) do
    sessions =
      SessionRegistry.list_active()
      |> Enum.map(fn session ->
        %{
          token_prefix: String.slice(session.token, 0, 8),
          agent_fingerprint: Identity.fingerprint(session.agent_id),
          kind: session.kind,
          working_dir: session.working_dir,
          owner_user_id: session.owner_user_id,
          created_at: session.created_at
        }
      end)

    {:ok, sessions}
  end
end

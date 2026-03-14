defmodule WorkersUniteWeb.OperatorMCP.Tools.CancelSession do
  @moduledoc """
  Cancels an active worker session by matching a token prefix.
  Finds the session in the SessionRegistry and invalidates it.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent.SessionRegistry
  alias WorkersUnite.Identity

  @impl true
  def definition do
    %{
      "name" => "wu_cancel_session",
      "description" =>
        "Cancels an active worker session. Provide the first 8 characters of the " <>
          "session token (shown when the session was started) to identify the session.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_token_prefix"],
        "properties" => %{
          "session_token_prefix" => %{
            "type" => "string",
            "description" => "First 8 characters of the session token"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"session_token_prefix" => prefix}, _context) when is_binary(prefix) do
    sessions = SessionRegistry.list_active()

    case Enum.find(sessions, fn session -> String.starts_with?(session.token, prefix) end) do
      nil ->
        {:error, :session_not_found}

      session ->
        :ok = SessionRegistry.invalidate(session.token)

        {:ok,
         %{
           cancelled: true,
           agent_fingerprint: Identity.fingerprint(session.agent_id),
           kind: session.kind,
           session_token_prefix: String.slice(session.token, 0, 8)
         }}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}
end

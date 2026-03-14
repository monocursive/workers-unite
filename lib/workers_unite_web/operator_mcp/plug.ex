defmodule WorkersUniteWeb.OperatorMCP.Plug do
  @moduledoc """
  HTTP transport endpoint for operator-facing MCP JSON-RPC requests.

  Authenticates via operator access tokens (not agent session tokens) and
  dispatches to the operator tool registry. Every successful tool call is
  logged as an audit record.
  """

  import Plug.Conn

  alias WorkersUnite.Operator
  alias WorkersUniteWeb.MCP.JsonRpc
  alias WorkersUniteWeb.OperatorMCP.ToolRegistry

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, access_token} <- verify(token),
         {:ok, request} <- JsonRpc.parse(conn.body_params) do
      context = build_context(access_token, conn)
      response = dispatch(request, context)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    else
      :error ->
        send_json(conn, 404, JsonRpc.error(nil, -32001, "unknown or invalid token"))

      {:error, code, message} ->
        send_json(conn, 400, JsonRpc.error(nil, code, message))
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> :error
    end
  end

  defp verify(token) do
    case Operator.verify_token(token) do
      {:ok, access_token} -> {:ok, access_token}
      :error -> :error
    end
  end

  defp build_context(access_token, _conn) do
    %{
      user_id: access_token.user_id,
      user: access_token.user,
      token_id: access_token.id,
      scopes: access_token.scopes,
      client_name: nil
    }
  end

  defp dispatch(%{id: id, method: "initialize", params: params}, _context) do
    client_name = get_in(params || %{}, ["clientInfo", "name"])
    if client_name, do: Process.put(:operator_client_name, client_name)

    JsonRpc.result(id, %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "workers_unite_operator", "version" => "0.1.0"}
    })
  end

  defp dispatch(%{id: id, method: "notifications/initialized"}, _context) do
    JsonRpc.result(id, %{})
  end

  defp dispatch(%{id: id, method: "tools/list"}, context) do
    JsonRpc.result(id, %{"tools" => ToolRegistry.list_for_scopes(context.scopes)})
  end

  defp dispatch(
         %{id: id, method: "tools/call", params: %{"name" => name} = params},
         context
       ) do
    arguments = Map.get(params, "arguments", %{})

    case ToolRegistry.dispatch(name, arguments, context) do
      {:ok, result} ->
        result_ref = extract_result_ref(result)
        audit_tool_call(name, arguments, "ok", context, result_ref: result_ref)
        JsonRpc.result(id, JsonRpc.tool_result(result))

      {:error, :unauthorized} ->
        audit_tool_call(name, arguments, "unauthorized", context)
        JsonRpc.error(id, -32003, "unauthorized tool")

      {:error, :tool_not_found} ->
        audit_tool_call(name, arguments, "not_found", context)
        JsonRpc.error(id, -32601, "tool not found")

      {:error, reason} ->
        audit_tool_call(name, arguments, "error", context)
        JsonRpc.error(id, -32000, humanize_error(reason))
    end
  end

  defp dispatch(%{id: id}, _context) do
    JsonRpc.error(id, -32601, "method not found")
  end

  @error_messages %{
    agent_not_found: "Agent not found",
    repo_not_found: "Repository not found",
    proposal_not_found: "Proposal not found",
    session_not_found: "Session not found",
    invalid_params: "Invalid parameters",
    invalid_repo_id: "Invalid repository ID",
    invalid_agent_id: "Invalid agent ID",
    invalid_git_ref: "Invalid git reference",
    invalid_kind: "Invalid agent kind",
    agent_limit_reached: "Agent limit reached",
    already_revoked: "Token already revoked",
    unauthorized: "Unauthorized"
  }

  defp humanize_error(reason) when is_atom(reason) do
    Map.get(@error_messages, reason, "Internal error")
  end

  defp humanize_error(reason) when is_binary(reason), do: reason

  defp humanize_error({_tag, message}) when is_binary(message), do: message

  defp humanize_error(_reason), do: "Internal error"

  defp extract_result_ref(%{event_ref: ref}) when is_binary(ref), do: ref
  defp extract_result_ref(_), do: nil

  defp audit_tool_call(tool_name, arguments, status, context, opts \\ []) do
    client_name = context.client_name || Process.get(:operator_client_name)

    Operator.log_tool_call(%{
      tool_name: tool_name,
      arguments_summary: summarize_arguments(arguments),
      result_status: status,
      result_ref: opts[:result_ref],
      client_name: client_name,
      user_id: context.user_id,
      token_id: context.token_id
    })
  end

  defp summarize_arguments(args) when is_map(args) do
    Map.new(args, fn
      {k, v} when is_binary(v) and byte_size(v) > 200 ->
        {k, String.slice(v, 0, 200) <> "..."}

      {k, v} ->
        {k, v}
    end)
  end

  defp summarize_arguments(_), do: %{}

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end

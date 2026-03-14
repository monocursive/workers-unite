defmodule WorkersUniteWeb.MCP.Plug do
  @moduledoc """
  HTTP transport endpoint for WorkersUnite MCP JSON-RPC requests.
  """

  import Plug.Conn

  alias WorkersUnite.Agent.SessionRegistry
  alias WorkersUniteWeb.MCP.{JsonRpc, ToolRegistry}

  def init(opts), do: opts

  def call(conn, _opts) do
    token = conn.path_params["token"]

    with {:ok, session} <- SessionRegistry.lookup(token),
         {:ok, request} <- JsonRpc.parse(conn.body_params) do
      response = dispatch(request, session, token)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    else
      :error ->
        send_json(conn, 404, JsonRpc.error(nil, -32001, "unknown session"))

      {:error, code, message} ->
        send_json(conn, 400, JsonRpc.error(nil, code, message))
    end
  end

  defp dispatch(%{id: id, method: "initialize"}, _session, _token) do
    JsonRpc.result(id, %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "workers_unite", "version" => "0.1.0"}
    })
  end

  defp dispatch(%{id: id, method: "notifications/initialized"}, _session, _token) do
    JsonRpc.result(id, %{})
  end

  defp dispatch(%{id: id, method: "tools/list"}, session, _token) do
    JsonRpc.result(id, %{"tools" => ToolRegistry.list_for_kind(session.kind)})
  end

  defp dispatch(
         %{id: id, method: "tools/call", params: %{"name" => name} = params},
         session,
         token
       ) do
    context = Map.merge(session, %{session_token: token})
    arguments = Map.get(params, "arguments", %{})

    case ToolRegistry.dispatch(name, arguments, context) do
      {:ok, result} -> JsonRpc.result(id, JsonRpc.tool_result(result))
      {:error, :unauthorized} -> JsonRpc.error(id, -32003, "unauthorized tool")
      {:error, :tool_not_found} -> JsonRpc.error(id, -32601, "tool not found")
      {:error, reason} -> JsonRpc.error(id, -32000, inspect(reason))
    end
  end

  defp dispatch(%{id: id}, _session, _token) do
    JsonRpc.error(id, -32601, "method not found")
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end

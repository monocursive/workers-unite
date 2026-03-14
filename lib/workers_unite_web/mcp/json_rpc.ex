defmodule WorkersUniteWeb.MCP.JsonRpc do
  @moduledoc """
  Minimal JSON-RPC 2.0 helpers for WorkersUnite MCP.
  """

  def parse(%{"jsonrpc" => "2.0", "method" => method} = payload) when is_binary(method) do
    {:ok,
     %{
       id: Map.get(payload, "id"),
       method: method,
       params: Map.get(payload, "params", %{})
     }}
  end

  def parse(_payload), do: {:error, -32600, "invalid request"}

  def result(id, data), do: %{"jsonrpc" => "2.0", "id" => id, "result" => data}

  def error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  def tool_result(data) do
    %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(data)}],
      "structuredContent" => data
    }
  end
end

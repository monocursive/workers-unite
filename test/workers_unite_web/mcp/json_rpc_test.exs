defmodule WorkersUniteWeb.MCP.JsonRpcTest do
  use ExUnit.Case, async: true

  alias WorkersUniteWeb.MCP.JsonRpc

  test "parses a valid request" do
    assert {:ok, %{id: 1, method: "tools/list", params: %{"foo" => "bar"}}} =
             JsonRpc.parse(%{
               "jsonrpc" => "2.0",
               "method" => "tools/list",
               "params" => %{"foo" => "bar"},
               "id" => 1
             })
  end

  test "rejects malformed payloads" do
    assert {:error, -32600, "invalid request"} = JsonRpc.parse(%{"method" => "tools/list"})
  end
end

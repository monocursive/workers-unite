defmodule WorkersUniteWeb.OperatorMCP.PlugTest do
  use WorkersUniteWeb.ConnCase, async: true

  import WorkersUnite.AccountsFixtures
  import WorkersUnite.OperatorFixtures

  alias WorkersUnite.Operator

  setup do
    user = onboarded_user_fixture()
    {plaintext, token} = operator_token_fixture(user)
    %{user: user, plaintext: plaintext, token: token}
  end

  defp jsonrpc_post(conn, plaintext, method, params \\ %{}, id \\ 1) do
    conn
    |> put_req_header("authorization", "Bearer #{plaintext}")
    |> put_req_header("content-type", "application/json")
    |> post("/operator/mcp", %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    })
  end

  describe "initialize" do
    test "returns protocol info with valid token", %{conn: conn, plaintext: plaintext} do
      conn = jsonrpc_post(conn, plaintext, "initialize")

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{
                 "protocolVersion" => "2024-11-05",
                 "capabilities" => %{"tools" => %{}},
                 "serverInfo" => %{"name" => "workers_unite_operator", "version" => "0.1.0"}
               }
             } = json_response(conn, 200)
    end
  end

  describe "authentication" do
    test "returns 404 with missing authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/operator/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{}
        })

      assert %{"error" => %{"code" => -32001, "message" => "unknown or invalid token"}} =
               json_response(conn, 404)
    end

    test "returns 404 with invalid token", %{conn: conn} do
      conn =
        jsonrpc_post(
          conn,
          "deadbeef00000000000000000000000000000000000000000000000000000000",
          "initialize"
        )

      assert %{"error" => %{"code" => -32001, "message" => "unknown or invalid token"}} =
               json_response(conn, 404)
    end

    test "returns 404 with revoked token", %{
      conn: conn,
      plaintext: plaintext,
      token: token,
      user: user
    } do
      {:ok, _revoked} = Operator.revoke_token(token.id, user)

      conn = jsonrpc_post(conn, plaintext, "initialize")

      assert %{"error" => %{"code" => -32001, "message" => "unknown or invalid token"}} =
               json_response(conn, 404)
    end
  end

  describe "tools/list" do
    test "returns tool definitions for observe scope", %{conn: conn, user: user} do
      {plaintext, _token} = operator_token_fixture(user, scopes: ["observe"])

      conn = jsonrpc_post(conn, plaintext, "tools/list")

      assert %{"result" => %{"tools" => tools}} = json_response(conn, 200)
      assert is_list(tools)
      assert Enum.any?(tools, &(&1["name"] == "wu_list_agents"))
      refute Enum.any?(tools, &(&1["name"] == "wu_dispatch_work"))
    end
  end

  describe "tools/call" do
    test "returns -32003 error for unauthorized scope", %{conn: conn, user: user} do
      # Create token with only observe scope, then try to call a control tool
      {plaintext, _token} = operator_token_fixture(user, scopes: ["observe"])

      conn =
        jsonrpc_post(conn, plaintext, "tools/call", %{
          "name" => "wu_dispatch_work",
          "arguments" => %{}
        })

      assert %{"error" => %{"code" => -32003, "message" => "unauthorized tool"}} =
               json_response(conn, 200)
    end

    test "creates an audit record on tool call", %{conn: conn, plaintext: plaintext} do
      _conn =
        jsonrpc_post(conn, plaintext, "tools/call", %{
          "name" => "wu_list_agents",
          "arguments" => %{}
        })

      audits = Operator.list_audits()
      assert [audit | _] = audits
      assert audit.tool_name == "wu_list_agents"
      assert audit.result_status == "ok"
    end

    test "returns -32601 and creates not_found audit for non-existent tool", %{
      conn: conn,
      plaintext: plaintext
    } do
      conn =
        jsonrpc_post(conn, plaintext, "tools/call", %{
          "name" => "wu_nonexistent_tool",
          "arguments" => %{}
        })

      assert %{"error" => %{"code" => -32601, "message" => "tool not found"}} =
               json_response(conn, 200)

      audits = Operator.list_audits()
      assert [audit | _] = audits
      assert audit.tool_name == "wu_nonexistent_tool"
      assert audit.result_status == "not_found"
    end
  end
end

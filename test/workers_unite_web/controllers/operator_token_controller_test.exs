defmodule WorkersUniteWeb.OperatorTokenControllerTest do
  use WorkersUniteWeb.ConnCase

  import WorkersUnite.OperatorFixtures

  setup :register_and_log_in_onboarded_user

  describe "POST /operator/tokens" do
    test "returns 201 with valid name and scopes, includes plaintext", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/operator/tokens", %{name: "ci-token", scopes: ["observe", "control"]})

      assert %{"token" => token, "plaintext" => plaintext} = json_response(conn, 201)
      assert token["name"] == "ci-token"
      assert token["scopes"] == ["observe", "control"]
      assert token["id"]
      assert token["token_prefix"]
      assert token["inserted_at"]
      assert is_binary(plaintext)
      assert String.length(plaintext) > 0
    end

    test "returns 400 when name and scopes are missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/operator/tokens", %{})

      assert %{"error" => "name and scopes are required"} = json_response(conn, 400)
    end

    test "returns 422 when scopes list is empty", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/operator/tokens", %{name: "bad-token", scopes: []})

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["scopes"]
    end
  end

  describe "GET /operator/tokens" do
    test "returns list of tokens", %{conn: conn, user: user} do
      {_plaintext1, token1} = operator_token_fixture(user, name: "token-a")
      {_plaintext2, token2} = operator_token_fixture(user, name: "token-b")

      conn = get(conn, ~p"/operator/tokens")

      assert %{"tokens" => tokens} = json_response(conn, 200)
      assert is_list(tokens)
      assert length(tokens) == 2

      ids = Enum.map(tokens, & &1["id"])
      assert token1.id in ids
      assert token2.id in ids
    end
  end

  describe "DELETE /operator/tokens/:id" do
    test "returns success for existing token", %{conn: conn, user: user} do
      {_plaintext, token} = operator_token_fixture(user)

      conn = delete(conn, ~p"/operator/tokens/#{token.id}")

      assert %{"ok" => true} = json_response(conn, 200)
    end

    test "returns 404 for non-existent token", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/operator/tokens/#{fake_id}")

      assert %{"error" => "Token not found"} = json_response(conn, 404)
    end

    test "returns 409 for already-revoked token", %{conn: conn, user: user} do
      {_plaintext, token} = operator_token_fixture(user)

      # Revoke it first
      {:ok, _} = WorkersUnite.Operator.revoke_token(token.id, user)

      conn = delete(conn, ~p"/operator/tokens/#{token.id}")

      assert %{"error" => "Token already revoked"} = json_response(conn, 409)
    end
  end

  describe "authentication" do
    test "unauthenticated request redirects" do
      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> get(~p"/operator/tokens")

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end

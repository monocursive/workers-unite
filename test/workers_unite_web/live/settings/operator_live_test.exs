defmodule WorkersUniteWeb.Settings.OperatorLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest
  import WorkersUnite.OperatorFixtures

  setup :register_and_log_in_onboarded_user

  test "renders operator tokens page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/operator")
    assert html =~ "Operator Tokens"
    assert html =~ "Connect OpenCode"
    assert html =~ "Create Token"
  end

  test "creates a token and shows plaintext", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/operator")

    html =
      view
      |> form("form", %{
        "token" => %{
          "name" => "test-token",
          "scope_observe" => "true",
          "scope_control" => "false"
        }
      })
      |> render_submit()

    assert html =~ "Token created"
    assert html =~ "Copy"
  end

  test "creates a token with expiration", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/operator")

    html =
      view
      |> form("form", %{
        "token" => %{
          "name" => "expiring-token",
          "scope_observe" => "true",
          "scope_control" => "false",
          "expires_in" => "30"
        }
      })
      |> render_submit()

    assert html =~ "Token created"
  end

  test "revokes a token", %{conn: conn, user: user} do
    {_plaintext, token} = operator_token_fixture(user)
    {:ok, view, html} = live(conn, "/settings/operator")

    assert html =~ token.name

    html =
      view
      |> element("button[phx-value-id='#{token.id}']")
      |> render_click()

    assert html =~ "Token revoked"
  end

  test "shows scope descriptions in form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/operator")
    assert html =~ "Read-only access to agents, repos, events, and sessions"
    assert html =~ "Publish intents, cast votes, dispatch work, cancel sessions"
  end

  test "shows MCP config with Bearer auth", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/operator")
    assert html =~ "Authorization"
    assert html =~ "Bearer"
    assert html =~ "/operator/mcp"
  end

  test "requires admin access" do
    conn = build_conn()
    conn = get(conn, "/settings/operator")
    assert redirected_to(conn) == "/users/log-in"
  end
end

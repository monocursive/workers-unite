defmodule ForgeletWeb.Settings.CredentialsLiveTest do
  use ForgeletWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders credentials page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/credentials")
    assert html =~ "API Credentials"
  end

  test "shows providers from runtime registry", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/credentials")
    assert html =~ "claude_code"
  end

  test "credential values are never shown in full after save", %{conn: conn, user: user} do
    Forgelet.Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "sk-secret-123", user.id)
    {:ok, _view, html} = live(conn, "/settings/credentials")

    refute html =~ "sk-secret-123"
    assert html =~ "configured"
  end
end

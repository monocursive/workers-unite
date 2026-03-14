defmodule WorkersUniteWeb.Settings.CredentialsLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders credentials page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/credentials")
    assert html =~ "API Credentials"
  end

  test "shows providers from provider registry", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/credentials")
    assert html =~ "Anthropic"
  end

  test "credential values are never shown in full after save", %{conn: conn, user: user} do
    WorkersUnite.Credentials.upsert("anthropic", "ANTHROPIC_API_KEY", "sk-secret-123", user.id)
    {:ok, _view, html} = live(conn, "/settings/credentials")

    refute html =~ "sk-secret-123"
    assert html =~ "configured"
  end
end

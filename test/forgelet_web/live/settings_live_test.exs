defmodule ForgeletWeb.SettingsLiveTest do
  use ForgeletWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders settings page for admin", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")
    assert html =~ "Instance Settings"
    assert html =~ "API Credentials"
    assert html =~ "Orchestrator Personality"
  end

  test "redirects unauthenticated users to login" do
    conn = build_conn()
    conn = get(conn, "/settings")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end

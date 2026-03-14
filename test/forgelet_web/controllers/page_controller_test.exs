defmodule ForgeletWeb.PageControllerTest do
  use ForgeletWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "GET / redirects to dashboard live view", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Mission Control"
  end

  test "GET / redirects to login when unauthenticated" do
    conn = build_conn()
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end

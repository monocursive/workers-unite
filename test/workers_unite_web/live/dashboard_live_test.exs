defmodule WorkersUniteWeb.DashboardLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders dashboard with stats", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Instance Overview"
    assert html =~ "Events"
    assert html =~ "Agents"
    assert html =~ "Repos"
  end
end

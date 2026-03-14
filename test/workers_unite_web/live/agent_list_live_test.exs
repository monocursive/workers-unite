defmodule WorkersUniteWeb.AgentListLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders agent list", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/agents")

    assert html =~ "Agents"
  end
end

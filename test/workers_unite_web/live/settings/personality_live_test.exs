defmodule WorkersUniteWeb.Settings.PersonalityLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders personality page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/personality")
    assert html =~ "Orchestrator Personality"
  end

  test "loads existing personality", %{conn: conn, user: user} do
    WorkersUnite.Settings.update(%{master_plan_personality: "Be careful."}, user.id)
    {:ok, _view, html} = live(conn, "/settings/personality")
    assert html =~ "Be careful."
  end

  test "saves personality", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/personality")

    view
    |> form("form", settings: %{personality: "Prioritize tests."})
    |> render_submit()

    assert WorkersUnite.Settings.get_personality() == "Prioritize tests."
  end

  test "blank personality is allowed", %{conn: conn, user: user} do
    # Set a value first
    WorkersUnite.Settings.update(%{master_plan_personality: "Something."}, user.id)
    {:ok, view, _html} = live(conn, "/settings/personality")

    view
    |> form("form", settings: %{personality: ""})
    |> render_submit()

    personality = WorkersUnite.Settings.get_personality()
    assert personality in [nil, ""]
  end
end

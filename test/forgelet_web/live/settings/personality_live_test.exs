defmodule ForgeletWeb.Settings.PersonalityLiveTest do
  use ForgeletWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders personality page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/personality")
    assert html =~ "Orchestrator Personality"
  end

  test "loads existing personality", %{conn: conn, user: user} do
    Forgelet.Settings.update(%{master_plan_personality: "Be careful."}, user.id)
    {:ok, _view, html} = live(conn, "/settings/personality")
    assert html =~ "Be careful."
  end

  test "saves personality", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/personality")

    view
    |> form("form", settings: %{personality: "Prioritize tests."})
    |> render_submit()

    assert Forgelet.Settings.get_personality() == "Prioritize tests."
  end

  test "blank personality is allowed", %{conn: conn, user: user} do
    # Set a value first
    Forgelet.Settings.update(%{master_plan_personality: "Something."}, user.id)
    {:ok, view, _html} = live(conn, "/settings/personality")

    view
    |> form("form", settings: %{personality: ""})
    |> render_submit()

    personality = Forgelet.Settings.get_personality()
    assert personality in [nil, ""]
  end
end

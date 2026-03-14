defmodule WorkersUniteWeb.OnboardingLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest
  import WorkersUnite.AccountsFixtures

  test "renders first-run setup when no users exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/onboarding")
    assert html =~ "WorkersUnite"
    assert html =~ "First-run setup"
    assert html =~ "Create Admin Account"
    refute html =~ "Step"
  end

  test "redirects to / when onboarding already completed", %{conn: conn} do
    user = onboarded_user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/onboarding")
  end

  test "redirects to login if user exists but not authenticated", %{conn: conn} do
    _user = user_fixture()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, "/onboarding")
  end

  test "creates admin account and redirects", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/onboarding")

    view
    |> form("form", user: %{email: "admin@test.com", password: "supersecretpassword"})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/users/onboarding-login/"

    # Onboarding should be marked complete
    assert WorkersUnite.Settings.onboarding_completed?()
  end
end

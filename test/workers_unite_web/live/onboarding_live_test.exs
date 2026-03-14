defmodule WorkersUniteWeb.OnboardingLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest
  import WorkersUnite.AccountsFixtures

  test "renders first-run setup when no users exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/onboarding")

    assert has_element?(view, "#onboarding-account-form")
    assert has_element?(view, "h2", "Create Admin Account")
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

  test "create account renders session handoff and leaves onboarding incomplete", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/onboarding")

    view
    |> form("#onboarding-account-form",
      user: %{email: "admin@test.com", password: "supersecretpassword"}
    )
    |> render_submit()

    assert has_element?(view, "#onboarding-session-form")
    refute WorkersUnite.Settings.onboarding_completed?()
  end

  test "renders passkey step when authenticated and onboarding is incomplete", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/onboarding")

    assert has_element?(view, "#onboarding-passkey-register-btn")
    assert has_element?(view, "#onboarding-skip-passkey-btn")
  end

  test "skip completes onboarding and redirects to dashboard", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/onboarding")

    view
    |> element("#onboarding-skip-passkey-btn")
    |> render_click()

    {path, _flash} = assert_redirect(view)

    assert path == "/"
    assert WorkersUnite.Settings.onboarding_completed?()
    assert WorkersUnite.Accounts.get_user!(user.id).onboarding_completed_at
  end

  test "registered event completes onboarding and redirects to dashboard", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/onboarding")

    render_hook(view, "registered", %{})

    {path, _flash} = assert_redirect(view)

    assert path == "/"
    assert WorkersUnite.Settings.onboarding_completed?()
    assert WorkersUnite.Accounts.get_user!(user.id).onboarding_completed_at
  end
end

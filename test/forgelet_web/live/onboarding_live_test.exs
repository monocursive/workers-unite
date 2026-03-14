defmodule ForgeletWeb.OnboardingLiveTest do
  use ForgeletWeb.ConnCase

  import Phoenix.LiveViewTest
  import Forgelet.AccountsFixtures

  test "renders account step when no users exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/onboarding")
    assert html =~ "Create Admin Account"
    assert html =~ "Step 1 of 4"
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
end

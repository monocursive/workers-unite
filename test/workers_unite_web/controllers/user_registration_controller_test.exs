defmodule WorkersUniteWeb.UserRegistrationControllerTest do
  use WorkersUniteWeb.ConnCase, async: true

  describe "GET /users/register" do
    test "redirects to /onboarding", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      assert redirected_to(conn) == ~p"/onboarding"
    end
  end

  describe "POST /users/register" do
    test "redirects to /onboarding", %{conn: conn} do
      conn = post(conn, ~p"/users/register", %{"user" => %{"email" => "a@b.com"}})
      assert redirected_to(conn) == ~p"/onboarding"
    end
  end
end

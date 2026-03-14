defmodule ForgeletWeb.UserRegistrationControllerTest do
  use ForgeletWeb.ConnCase, async: true

  import Forgelet.AccountsFixtures

  describe "GET /users/register" do
    test "redirects to login when users exist", %{conn: conn} do
      _user = user_fixture()
      conn = get(conn, ~p"/users/register")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /users/register" do
    test "redirects to login when users exist", %{conn: conn} do
      _user = user_fixture()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes()
        })

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end

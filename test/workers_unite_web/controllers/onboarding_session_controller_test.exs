defmodule WorkersUniteWeb.OnboardingSessionControllerTest do
  use WorkersUniteWeb.ConnCase, async: true

  import Ecto.Query
  import WorkersUnite.AccountsFixtures

  alias WorkersUnite.Accounts
  alias WorkersUnite.Accounts.UserToken
  alias WorkersUnite.Repo

  describe "POST /onboarding/session" do
    test "valid token establishes session and redirects to onboarding", %{conn: conn} do
      user = user_fixture()
      token = Accounts.generate_onboarding_session_token(user)

      conn =
        post(conn, ~p"/onboarding/session", %{
          "onboarding_session" => %{"token" => token}
        })

      assert redirected_to(conn) == ~p"/onboarding"
      assert get_session(conn, :user_token)

      conn =
        conn
        |> recycle()
        |> get(~p"/onboarding")

      assert html_response(conn, 200) =~ "Add a passkey"
    end

    test "consumed token cannot be reused", %{conn: conn} do
      user = user_fixture()
      token = Accounts.generate_onboarding_session_token(user)

      conn =
        post(conn, ~p"/onboarding/session", %{
          "onboarding_session" => %{"token" => token}
        })

      assert redirected_to(conn) == ~p"/onboarding"

      conn =
        build_conn()
        |> post(~p"/onboarding/session", %{
          "onboarding_session" => %{"token" => token}
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your onboarding session expired. Please log in."

      refute get_session(conn, :user_token)
    end

    test "expired token redirects with error and no session", %{conn: conn} do
      user = user_fixture()
      token = Accounts.generate_onboarding_session_token(user)

      Repo.update_all(
        from(t in UserToken,
          where: t.context == "onboarding_session" and t.user_id == ^user.id
        ),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -120, :second)]
      )

      conn =
        post(conn, ~p"/onboarding/session", %{
          "onboarding_session" => %{"token" => token}
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your onboarding session expired. Please log in."

      refute get_session(conn, :user_token)
    end

    test "invalid token redirects with error and no session", %{conn: conn} do
      conn =
        post(conn, ~p"/onboarding/session", %{
          "onboarding_session" => %{"token" => "not-a-valid-token"}
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your onboarding session expired. Please log in."

      refute get_session(conn, :user_token)
    end
  end
end

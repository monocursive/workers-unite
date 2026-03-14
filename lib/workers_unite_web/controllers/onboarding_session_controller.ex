defmodule WorkersUniteWeb.OnboardingSessionController do
  @moduledoc "Consumes one-time onboarding handoff tokens and establishes a browser session."
  use WorkersUniteWeb, :controller

  alias WorkersUnite.Accounts
  alias WorkersUniteWeb.UserAuth

  def create(conn, %{"onboarding_session" => %{"token" => token}}) do
    case Accounts.consume_onboarding_session_token(token) do
      {:ok, user} ->
        conn
        |> UserAuth.establish_user_session(user)
        |> redirect(to: ~p"/onboarding")

      {:error, :invalid_or_expired} ->
        conn
        |> put_flash(:error, "Your onboarding session expired. Please log in.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Your onboarding session expired. Please log in.")
    |> redirect(to: ~p"/users/log-in")
  end
end

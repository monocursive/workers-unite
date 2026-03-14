defmodule ForgeletWeb.UserRegistrationController do
  @moduledoc "Handles first-user registration, rejecting signups once an admin account exists."
  use ForgeletWeb, :controller

  alias Forgelet.Accounts
  alias Forgelet.Accounts.User

  def new(conn, _params) do
    if not Accounts.first_user?() do
      conn
      |> put_flash(:error, "Registration is closed. Use onboarding to create the admin account.")
      |> redirect(to: ~p"/users/log-in")
    else
      changeset = Accounts.change_user_email(%User{})
      render(conn, :new, changeset: changeset)
    end
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_first_user(user_params) do
      {:error, :registration_closed} ->
        conn
        |> put_flash(:error, "Registration is closed.")
        |> redirect(to: ~p"/users/log-in")

      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        conn
        |> put_flash(
          :info,
          "An email was sent to #{user.email}, please access it to confirm your account."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end

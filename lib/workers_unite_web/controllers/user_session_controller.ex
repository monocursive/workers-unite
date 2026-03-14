defmodule WorkersUniteWeb.UserSessionController do
  @moduledoc "Handles user login (password), and logout."
  use WorkersUniteWeb, :controller

  require Logger

  alias WorkersUnite.Accounts
  alias WorkersUniteWeb.UserAuth

  def new(conn, _params) do
    email = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    form = Phoenix.Component.to_form(%{"email" => email}, as: "user")

    has_passkeys =
      if email, do: Accounts.has_passkeys?(conn.assigns.current_scope.user), else: false

    render(conn, :new, form: form, has_passkeys: has_passkeys)
  end

  # email + password login
  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      Logger.info("Successful password login", user_id: user.id, email: email)

      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      Logger.warning("Failed password login attempt", email: email)
      form = Phoenix.Component.to_form(user_params, as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> render(:new, form: form, has_passkeys: false)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end

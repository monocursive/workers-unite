defmodule ForgeletWeb.UserAuth do
  @moduledoc """
  Plug-based authentication helpers and LiveView `on_mount` callbacks for session management,
  login/logout, sudo mode, and onboarding guards.
  """

  use ForgeletWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Forgelet.Accounts
  alias Forgelet.Accounts.Scope

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_forgelet_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued.
  @session_reissue_age_in_days 7

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ForgeletWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        nil
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the user is already logged in
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id do
    conn
  end

  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    put_session(conn, :user_token, token)
  end

  @doc """
  Plug for routes that require sudo mode.
  """
  def require_sudo_mode(conn, _opts) do
    if Accounts.sudo_mode?(conn.assigns.current_scope.user, -10) do
      conn
    else
      conn
      |> put_flash(:error, "You must re-authenticate to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Plug for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  defp signed_in_path(_conn), do: ~p"/"

  @doc """
  Plug for routes that require the user to be authenticated.
  Redirects to onboarding if onboarding is not complete.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      if not Forgelet.Settings.onboarding_completed?() do
        conn
        |> redirect(to: ~p"/onboarding")
        |> halt()
      else
        conn
      end
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  ## on_mount callbacks for LiveView

  @doc """
  LiveView on_mount that ensures the user is authenticated.
  Redirects to onboarding if not yet completed.
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      if not Forgelet.Settings.onboarding_completed?() do
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/onboarding")}
      else
        {:cont, socket}
      end
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
       |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    cond do
      is_nil(socket.assigns.current_scope) || is_nil(socket.assigns.current_scope.user) ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      not Forgelet.Settings.onboarding_completed?() ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/onboarding")}

      socket.assigns.current_scope.user.role != "admin" ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      true ->
        {:cont, socket}
    end
  end

  def on_mount(:ensure_authenticated_for_onboarding, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    cond do
      Forgelet.Settings.onboarding_completed?() ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}

      Accounts.first_user?() ->
        # Allow unauthenticated access for step 1 (account creation)
        {:cont, socket}

      socket.assigns.current_scope ->
        {:cont, socket}

      true ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You must log in to continue onboarding.")
         |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")}
    end
  end

  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      if token = session["user_token"] do
        case Accounts.get_user_by_session_token(token) do
          {user, _inserted_at} -> Scope.for_user(user)
          nil -> nil
        end
      end
    end)
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end

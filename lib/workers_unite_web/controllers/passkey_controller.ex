defmodule WorkersUniteWeb.PasskeyController do
  @moduledoc "Handles passkey login, reauth, and registration JSON endpoints."
  use WorkersUniteWeb, :controller

  require Logger

  alias WorkersUnite.Accounts
  alias WorkersUniteWeb.UserAuth

  # --- Login ---

  def login_challenge(conn, params) do
    email = params["email"]
    {:ok, token, options} = Accounts.generate_webauthn_login_challenge(email)
    json(conn, %{token: token, options: options})
  end

  def login(conn, %{"token" => token, "assertion" => assertion}) do
    case Accounts.verify_webauthn_login(token, assertion) do
      {:ok, user} ->
        Logger.info("Successful passkey login", user_id: user.id, email: user.email)

        conn
        |> UserAuth.establish_user_session(user, %{"remember_me" => "true"})
        |> json(%{ok: true, redirect_to: ~p"/"})

      {:error, reason} ->
        Logger.warning("Failed passkey login attempt", reason: inspect(reason))
        render_reason(conn, :unauthorized, reason)
    end
  end

  # --- Reauth ---

  def reauth_challenge(conn, _params) do
    scope = conn.assigns.current_scope
    {:ok, token, options} = Accounts.generate_webauthn_reauth_challenge(scope)
    json(conn, %{token: token, options: options})
  end

  def reauth(conn, %{"token" => token, "assertion" => assertion}) do
    scope = conn.assigns.current_scope

    case Accounts.verify_webauthn_reauth(scope, token, assertion) do
      {:ok, user} ->
        conn
        |> UserAuth.establish_user_session(user)
        |> json(%{ok: true})

      {:error, reason} ->
        Logger.warning("Failed passkey reauth attempt",
          user_id: scope.user.id,
          reason: inspect(reason)
        )

        render_reason(conn, :unauthorized, reason)
    end
  end

  # --- Registration ---

  def registration_challenge(conn, _params) do
    scope = conn.assigns.current_scope
    {:ok, token, options} = Accounts.generate_webauthn_registration_challenge(scope)
    json(conn, %{token: token, options: options})
  end

  def register(conn, %{"token" => token, "attestation" => attestation} = params) do
    scope = conn.assigns.current_scope
    friendly_name = params["friendly_name"] || "Passkey"

    case Accounts.register_webauthn_credential(scope, token, attestation, friendly_name) do
      {:ok, _credential} ->
        json(conn, %{ok: true})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: errors})

      {:error, reason} ->
        Logger.warning(
          "Failed passkey registration attempt",
          user_id: scope.user.id,
          reason: inspect(reason)
        )

        render_reason(conn, :unprocessable_entity, reason)
    end
  end

  defp render_reason(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(%{error: reason_message(reason)})
  end

  defp reason_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_message(reason) when is_binary(reason), do: reason
  defp reason_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp reason_message(reason), do: inspect(reason)
end

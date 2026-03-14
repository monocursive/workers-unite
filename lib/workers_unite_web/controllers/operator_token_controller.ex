defmodule WorkersUniteWeb.OperatorTokenController do
  @moduledoc "JSON API controller for operator access token CRUD."
  use WorkersUniteWeb, :controller

  alias WorkersUnite.Operator

  def index(conn, _params) do
    user = conn.assigns.current_scope.user
    tokens = Operator.list_tokens(user)

    json(conn, %{
      tokens:
        Enum.map(tokens, fn t ->
          %{
            id: t.id,
            name: t.name,
            token_prefix: t.token_prefix,
            scopes: t.scopes,
            last_used_at: t.last_used_at,
            expires_at: t.expires_at,
            revoked_at: t.revoked_at,
            inserted_at: t.inserted_at
          }
        end)
    })
  end

  def create(conn, %{"name" => name, "scopes" => scopes} = params) do
    user = conn.assigns.current_scope.user
    opts = parse_expires_opts(params)

    case Operator.create_token(user, name, scopes, opts) do
      {:ok, plaintext, token} ->
        conn
        |> put_status(:created)
        |> json(%{
          token: %{
            id: token.id,
            name: token.name,
            token_prefix: token.token_prefix,
            scopes: token.scopes,
            expires_at: token.expires_at,
            inserted_at: token.inserted_at
          },
          plaintext: plaintext
        })

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "name and scopes are required"})
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    case Operator.revoke_token(id, user) do
      {:ok, _token} ->
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})

      {:error, :already_revoked} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Token already revoked"})
    end
  end

  defp parse_expires_opts(%{"expires_in_days" => days}) when is_integer(days) and days > 0 do
    [expires_at: DateTime.add(DateTime.utc_now(), days, :day)]
  end

  defp parse_expires_opts(%{"expires_at" => expires_at}) when is_binary(expires_at) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, dt, _} -> [expires_at: dt]
      _ -> []
    end
  end

  defp parse_expires_opts(_), do: []
end

defmodule WorkersUnite.Operator do
  @moduledoc """
  Context for operator API access tokens and tool call auditing.
  """

  import Ecto.Query, warn: false
  alias WorkersUnite.Repo
  alias WorkersUnite.Operator.{AccessToken, ToolAudit}

  ## Access Tokens

  @doc """
  Creates a new access token for the given user.

  Returns `{:ok, plaintext, token}` where `plaintext` is the hex-encoded
  token string shown once to the user, or `{:error, changeset}`.
  """
  def create_token(user, name, scopes, opts \\ []) do
    {plaintext, token_struct} = AccessToken.build_token(user)

    changeset =
      AccessToken.changeset(token_struct, %{
        name: name,
        scopes: scopes,
        expires_at: Keyword.get(opts, :expires_at)
      })

    case Repo.insert(changeset) do
      {:ok, token} -> {:ok, plaintext, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Lists all access tokens for a user, ordered by most recently created first.
  """
  def list_tokens(user) do
    from(t in AccessToken,
      where: t.user_id == ^user.id,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Revokes an access token by setting `revoked_at`.

  Returns `{:ok, token}` or `{:error, :not_found}`.
  """
  def revoke_token(token_id, user) do
    case Repo.get_by(AccessToken, id: token_id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      %{revoked_at: revoked_at} when not is_nil(revoked_at) ->
        {:error, :already_revoked}

      token ->
        token
        |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second))
        |> Repo.update()
    end
  end

  @doc """
  Verifies a plaintext hex token string.

  Hashes the token, looks up the matching non-revoked/non-expired record,
  updates `last_used_at`, and returns `{:ok, token_with_user}` or `:error`.
  """
  def verify_token(plaintext) do
    with {:ok, query} <- AccessToken.verify_token(plaintext),
         %AccessToken{} = token <- Repo.one(query) do
      # Update last_used_at asynchronously so it doesn't block the request path
      Task.start(fn ->
        token
        |> Ecto.Changeset.change(last_used_at: DateTime.utc_now(:second))
        |> Repo.update()
      end)

      {:ok, Repo.preload(token, :user)}
    else
      _ -> :error
    end
  end

  ## Tool Auditing

  @doc """
  Logs a tool call as an audit record.

  Accepts a map with keys matching `ToolAudit` fields.
  Returns `{:ok, audit}` or `{:error, changeset}`.
  """
  def log_tool_call(attrs) do
    %ToolAudit{}
    |> ToolAudit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists recent audit records.

  ## Options

    * `:user_id` — filter by user
    * `:limit` — max records to return (default 50)
  """
  def list_audits(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    user_id = Keyword.get(opts, :user_id)

    query =
      from(a in ToolAudit,
        order_by: [desc: a.inserted_at],
        limit: ^limit
      )

    query =
      if user_id do
        where(query, [a], a.user_id == ^user_id)
      else
        query
      end

    Repo.all(query)
  end
end

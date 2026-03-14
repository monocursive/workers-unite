defmodule WorkersUnite.Operator.AccessToken do
  @moduledoc """
  Schema and token helpers for operator API access tokens.

  Tokens are bearer credentials issued to users for programmatic access
  (e.g. from OpenCode or other MCP clients). The plaintext is shown once
  at creation time; only a SHA-256 hash is persisted.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32
  @valid_scopes ~w(observe control)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "operator_access_tokens" do
    field :name, :string
    field :token_prefix, :string
    field :token_hash, :binary
    field :scopes, {:array, :string}
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, WorkersUnite.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for inserting or updating an access token.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :token_prefix, :scopes, :expires_at, :user_id])
    |> validate_required([:name, :token_hash, :scopes])
    |> validate_length(:scopes, min: 1)
    |> validate_scopes()
    |> unique_constraint(:token_hash)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid = Enum.reject(scopes, &(&1 in @valid_scopes))

      if invalid == [] do
        []
      else
        [{:scopes, "contains invalid scopes: #{Enum.join(invalid, ", ")}"}]
      end
    end)
  end

  @doc """
  Generates a new access token for the given user.

  Returns `{plaintext_hex, %AccessToken{}}` where the plaintext is a 64-char
  hex string shown once to the user, and the struct contains the SHA-256 hash
  ready for insertion.
  """
  def build_token(user) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    plaintext = Base.encode16(raw, case: :lower)
    hash = :crypto.hash(@hash_algorithm, raw)
    prefix = String.slice(plaintext, 0, 8)

    {plaintext,
     %__MODULE__{
       token_hash: hash,
       token_prefix: prefix,
       user_id: user.id
     }}
  end

  @doc """
  Builds an Ecto query that finds a non-revoked, non-expired token matching
  the given hex plaintext, with the user preloaded.

  Returns `:error` if the plaintext is not valid hex.
  """
  def verify_token(plaintext_hex) do
    case Base.decode16(plaintext_hex, case: :mixed) do
      {:ok, raw} ->
        hash = :crypto.hash(@hash_algorithm, raw)
        now = DateTime.utc_now()

        query =
          from t in __MODULE__,
            where: t.token_hash == ^hash,
            where: is_nil(t.revoked_at),
            where: is_nil(t.expires_at) or t.expires_at > ^now,
            preload: [:user]

        {:ok, query}

      :error ->
        :error
    end
  end
end

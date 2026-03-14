defmodule WorkersUnite.Accounts.WebauthnChallenge do
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32
  @challenge_validity_seconds 120

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webauthn_challenges" do
    field :token_hash, :binary
    field :purpose, :string
    field :challenge_data, :binary
    field :expires_at, :utc_datetime
    belongs_to :user, WorkersUnite.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a challenge record, returning {url_safe_token, %WebauthnChallenge{}}.
  The raw token is given to the client; the hash is stored.
  """
  def build(purpose, challenge_struct, user_id \\ nil) do
    token = :crypto.strong_rand_bytes(@rand_size)
    token_hash = :crypto.hash(@hash_algorithm, token)
    encoded_token = Base.url_encode64(token, padding: false)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@challenge_validity_seconds, :second)
      |> DateTime.truncate(:second)

    challenge_binary = :erlang.term_to_binary(challenge_struct)

    record = %__MODULE__{
      token_hash: token_hash,
      purpose: to_string(purpose),
      challenge_data: challenge_binary,
      user_id: user_id,
      expires_at: expires_at
    }

    {encoded_token, record}
  end

  @doc """
  Returns a query that finds a valid (non-expired, matching) challenge and deletes it.
  Returns the deserialized challenge struct on success.
  """
  def consume_token_query(token, purpose) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        token_hash = :crypto.hash(@hash_algorithm, decoded_token)
        now = DateTime.utc_now()

        query =
          from c in __MODULE__,
            where: c.token_hash == ^token_hash,
            where: c.purpose == ^to_string(purpose),
            where: c.expires_at > ^now

        {:ok, query}

      :error ->
        :error
    end
  end
end

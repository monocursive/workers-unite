defmodule WorkersUnite.OperatorFixtures do
  @moduledoc """
  Test helpers for creating operator access tokens.
  """

  alias WorkersUnite.Operator

  @doc """
  Creates an operator access token for the given user.

  Returns `{plaintext, token}` where `plaintext` is the hex-encoded token string.

  ## Options

    * `:name` — token name (default: "test-token")
    * `:scopes` — list of scopes (default: ["observe", "control"])
    * `:expires_at` — optional expiration DateTime
  """
  def operator_token_fixture(user, opts \\ []) do
    name = Keyword.get(opts, :name, "test-token")
    scopes = Keyword.get(opts, :scopes, ["observe", "control"])
    create_opts = Keyword.take(opts, [:expires_at])

    {:ok, plaintext, token} = Operator.create_token(user, name, scopes, create_opts)
    {plaintext, token}
  end
end

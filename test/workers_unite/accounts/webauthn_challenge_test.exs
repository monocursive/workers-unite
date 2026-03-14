defmodule WorkersUnite.Accounts.WebauthnChallengeTest do
  use WorkersUnite.DataCase, async: true

  alias WorkersUnite.Accounts.WebauthnChallenge

  import WorkersUnite.AccountsFixtures

  describe "build/3" do
    test "returns a url-safe token and a valid challenge record" do
      user = user_fixture()
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}

      {token, record} = WebauthnChallenge.build("registration", challenge_struct, user.id)

      assert is_binary(token)
      # Token must be valid base64url
      assert {:ok, _decoded} = Base.url_decode64(token, padding: false)

      assert %WebauthnChallenge{} = record
      assert record.purpose == "registration"
      assert record.user_id == user.id
      assert is_binary(record.token_hash)
      assert is_binary(record.challenge_data)
      assert %DateTime{} = record.expires_at
      # Expires in the future
      assert DateTime.compare(record.expires_at, DateTime.utc_now()) == :gt
    end

    test "builds without a user_id (discoverable credential flow)" do
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}

      {token, record} = WebauthnChallenge.build("login", challenge_struct)

      assert is_binary(token)
      assert record.purpose == "login"
      assert is_nil(record.user_id)
    end

    test "challenge_data round-trips through term_to_binary" do
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}
      {_token, record} = WebauthnChallenge.build("registration", challenge_struct)

      recovered = :erlang.binary_to_term(record.challenge_data, [:safe])
      assert recovered == challenge_struct
    end

    test "token hash is the SHA-256 of the raw token bytes" do
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}
      {token, record} = WebauthnChallenge.build("registration", challenge_struct)

      {:ok, raw} = Base.url_decode64(token, padding: false)
      assert record.token_hash == :crypto.hash(:sha256, raw)
    end
  end

  describe "consume_token_query/2" do
    test "returns {:ok, query} for a valid token and purpose" do
      user = user_fixture()
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}
      {token, record} = WebauthnChallenge.build("registration", challenge_struct, user.id)

      Repo.insert!(record)

      assert {:ok, query} = WebauthnChallenge.consume_token_query(token, "registration")
      assert %WebauthnChallenge{} = Repo.one(query)
    end

    test "returns :error for invalid base64 token" do
      assert :error = WebauthnChallenge.consume_token_query("not!!valid!!base64", "registration")
    end

    test "does not match when purpose differs" do
      user = user_fixture()
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}
      {token, record} = WebauthnChallenge.build("registration", challenge_struct, user.id)

      Repo.insert!(record)

      assert {:ok, query} = WebauthnChallenge.consume_token_query(token, "login")
      refute Repo.one(query)
    end

    test "does not match a different token value" do
      user = user_fixture()
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}
      {_token, record} = WebauthnChallenge.build("registration", challenge_struct, user.id)

      Repo.insert!(record)

      # Build a completely different token
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      assert {:ok, query} = WebauthnChallenge.consume_token_query(fake_token, "registration")
      refute Repo.one(query)
    end

    test "excludes expired challenges" do
      user = user_fixture()
      challenge_struct = %{bytes: :crypto.strong_rand_bytes(32), rp_id: "localhost"}
      {token, record} = WebauthnChallenge.build("registration", challenge_struct, user.id)

      # Insert with an already-expired timestamp
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-300, :second)
        |> DateTime.truncate(:second)

      expired_record = %{record | expires_at: expired_at}
      Repo.insert!(expired_record)

      assert {:ok, query} = WebauthnChallenge.consume_token_query(token, "registration")
      refute Repo.one(query)
    end
  end
end

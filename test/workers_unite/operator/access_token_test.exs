defmodule WorkersUnite.Operator.AccessTokenTest do
  use WorkersUnite.DataCase

  import WorkersUnite.AccountsFixtures

  alias WorkersUnite.Operator.AccessToken

  describe "build_token/1" do
    test "returns {plaintext, %AccessToken{}} with hash and prefix set" do
      user = onboarded_user_fixture()
      {plaintext, %AccessToken{} = token} = AccessToken.build_token(user)

      assert is_binary(plaintext)
      assert byte_size(plaintext) == 64
      assert token.token_hash != nil
      assert is_binary(token.token_hash)
      assert token.token_prefix == String.slice(plaintext, 0, 8)
      assert token.user_id == user.id
    end
  end

  describe "changeset/2" do
    test "requires name" do
      changeset =
        AccessToken.changeset(%AccessToken{}, %{
          token_hash: :crypto.strong_rand_bytes(32),
          scopes: ["observe"]
        })

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires scopes to be non-empty" do
      changeset =
        AccessToken.changeset(%AccessToken{}, %{
          name: "my token",
          token_hash: :crypto.strong_rand_bytes(32),
          scopes: []
        })

      assert %{scopes: [msg]} = errors_on(changeset)
      assert msg =~ "should have at least 1 item"
    end

    test "rejects invalid scopes" do
      changeset =
        AccessToken.changeset(%AccessToken{}, %{
          name: "my token",
          token_hash: :crypto.strong_rand_bytes(32),
          scopes: ["admin", "foo"]
        })

      assert %{scopes: [msg]} = errors_on(changeset)
      assert msg =~ "invalid scopes"
    end

    test "accepts valid scopes" do
      base = %{name: "my token", token_hash: :crypto.strong_rand_bytes(32)}

      for scopes <- [["observe"], ["control"], ["observe", "control"]] do
        changeset = AccessToken.changeset(%AccessToken{}, Map.put(base, :scopes, scopes))
        assert changeset.valid?, "expected #{inspect(scopes)} to be valid"
      end
    end
  end

  describe "verify_token/1" do
    test "returns {:ok, query} for valid hex" do
      user = onboarded_user_fixture()
      {plaintext, _token} = AccessToken.build_token(user)

      assert {:ok, %Ecto.Query{}} = AccessToken.verify_token(plaintext)
    end

    test "returns :error for invalid hex" do
      assert :error = AccessToken.verify_token("not-valid-hex!!!")
    end
  end
end

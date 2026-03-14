defmodule WorkersUnite.OperatorTest do
  use WorkersUnite.DataCase

  import WorkersUnite.AccountsFixtures
  import WorkersUnite.OperatorFixtures

  alias WorkersUnite.Operator

  setup do
    %{user: onboarded_user_fixture()}
  end

  describe "create_token/4" do
    test "returns {:ok, plaintext, token} with valid params", %{user: user} do
      assert {:ok, plaintext, token} =
               Operator.create_token(user, "my-token", ["observe", "control"])

      assert is_binary(plaintext)
      assert String.length(plaintext) == 64
      assert token.name == "my-token"
      assert token.scopes == ["observe", "control"]
      assert token.user_id == user.id
      assert is_nil(token.revoked_at)
    end

    test "returns {:error, changeset} with empty scopes", %{user: user} do
      assert {:error, %Ecto.Changeset{}} =
               Operator.create_token(user, "bad-token", [])
    end
  end

  describe "verify_token/1" do
    test "returns {:ok, token} for a valid plaintext", %{user: user} do
      {plaintext, _token} = operator_token_fixture(user)

      assert {:ok, verified} = Operator.verify_token(plaintext)
      assert verified.user_id == user.id
      assert verified.user.id == user.id
    end

    test "returns :error for a revoked token", %{user: user} do
      {plaintext, token} = operator_token_fixture(user)

      {:ok, _revoked} = Operator.revoke_token(token.id, user)

      assert :error = Operator.verify_token(plaintext)
    end

    test "returns :error for an expired token", %{user: user} do
      past = DateTime.add(DateTime.utc_now(:second), -3600, :second)

      {plaintext, _token} =
        operator_token_fixture(user, expires_at: past)

      assert :error = Operator.verify_token(plaintext)
    end
  end

  describe "revoke_token/2" do
    test "sets revoked_at", %{user: user} do
      {_plaintext, token} = operator_token_fixture(user)
      assert is_nil(token.revoked_at)

      assert {:ok, revoked} = Operator.revoke_token(token.id, user)
      assert not is_nil(revoked.revoked_at)
    end

    test "returns {:error, :already_revoked} on already-revoked token", %{user: user} do
      {_plaintext, token} = operator_token_fixture(user)

      {:ok, _revoked} = Operator.revoke_token(token.id, user)
      assert {:error, :already_revoked} = Operator.revoke_token(token.id, user)
    end
  end

  describe "list_tokens/1" do
    test "returns tokens for the user", %{user: user} do
      {_p1, token1} = operator_token_fixture(user, name: "token-a")
      {_p2, token2} = operator_token_fixture(user, name: "token-b")

      tokens = Operator.list_tokens(user)
      token_ids = Enum.map(tokens, & &1.id)

      assert token1.id in token_ids
      assert token2.id in token_ids
    end
  end
end

defmodule Forgelet.CredentialsTest do
  use Forgelet.DataCase

  alias Forgelet.Credentials

  test "upsert creates a new credential" do
    assert {:ok, cred} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "sk-test-key")
    assert cred.provider == "claude_code"
    assert cred.key_name == "ANTHROPIC_API_KEY"
    assert is_binary(cred.encrypted_value)
  end

  test "upsert updates existing credential" do
    {:ok, cred1} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "old-key")
    {:ok, cred2} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "new-key")

    assert cred1.id == cred2.id
    assert Credentials.get_decrypted("claude_code", "ANTHROPIC_API_KEY") == "new-key"
  end

  test "list returns all credentials" do
    {:ok, _} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "key1")
    {:ok, _} = Credentials.upsert("codex", "OPENAI_API_KEY", "key2")

    list = Credentials.list()
    assert length(list) == 2
  end

  test "delete removes a credential" do
    {:ok, cred} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "key1")
    assert {:ok, _} = Credentials.delete(cred.id)
    assert Credentials.get_decrypted("claude_code", "ANTHROPIC_API_KEY") == nil
  end

  test "delete returns error for missing id" do
    assert {:error, :not_found} = Credentials.delete(Ecto.UUID.generate())
  end

  test "get_decrypted returns decrypted value" do
    {:ok, _} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "my-secret")
    assert Credentials.get_decrypted("claude_code", "ANTHROPIC_API_KEY") == "my-secret"
  end

  test "get_decrypted returns nil for missing credential" do
    assert Credentials.get_decrypted("nonexistent", "KEY") == nil
  end

  test "all_decrypted_for_provider returns map of decrypted values" do
    {:ok, _} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "key-a")
    {:ok, _} = Credentials.upsert("claude_code", "OTHER_KEY", "key-b")

    result = Credentials.all_decrypted_for_provider("claude_code")
    assert result == %{"ANTHROPIC_API_KEY" => "key-a", "OTHER_KEY" => "key-b"}
  end

  test "unique constraint on provider + key_name" do
    {:ok, _} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "v1")
    # Second upsert should update, not error
    {:ok, _} = Credentials.upsert("claude_code", "ANTHROPIC_API_KEY", "v2")
    assert length(Credentials.list()) == 1
  end
end

defmodule WorkersUnite.Identity.VaultTest do
  use ExUnit.Case

  alias WorkersUnite.Identity.Vault

  defp tmp_key_path do
    dir = Path.join(System.tmp_dir!(), "vault_test_#{System.unique_integer([:positive])}")
    path = Path.join(dir, "node.key")

    on_exit(fn -> File.rm_rf!(dir) end)

    path
  end

  test "generates keypair when no file exists" do
    path = tmp_key_path()
    name = :"vault_#{System.unique_integer([:positive])}"

    start_supervised!({Vault, name: name, key_path: path})

    pub = Vault.public_key(name)
    assert is_binary(pub)
    assert byte_size(pub) == 32
  end

  test "persists and reloads same key" do
    path = tmp_key_path()
    name = :"vault_#{System.unique_integer([:positive])}"

    start_supervised!({Vault, name: name, key_path: path}, id: :vault_first)
    pub1 = Vault.public_key(name)
    stop_supervised!(:vault_first)

    name2 = :"vault_#{System.unique_integer([:positive])}"
    start_supervised!({Vault, name: name2, key_path: path}, id: :vault_second)
    pub2 = Vault.public_key(name2)

    assert pub1 == pub2
  end

  test "sign produces valid signature" do
    path = tmp_key_path()
    name = :"vault_#{System.unique_integer([:positive])}"

    start_supervised!({Vault, name: name, key_path: path})

    data = "hello workers_unite"
    signature = Vault.sign(data, name)
    pub = Vault.public_key(name)

    assert WorkersUnite.Identity.verify(data, signature, pub)
  end

  test "fingerprint returns 16-char hex" do
    path = tmp_key_path()
    name = :"vault_#{System.unique_integer([:positive])}"

    start_supervised!({Vault, name: name, key_path: path})

    fp = Vault.fingerprint(name)
    assert is_binary(fp)
    assert String.length(fp) == 16
    assert Regex.match?(~r/\A[0-9a-f]{16}\z/, fp)
  end
end

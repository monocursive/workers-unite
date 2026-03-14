defmodule WorkersUnite.Credentials.EncryptionTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Credentials.Encryption

  test "roundtrip encrypt/decrypt" do
    plaintext = "sk-ant-api03-secret-key-value"
    encrypted = Encryption.encrypt(plaintext)

    assert is_binary(encrypted)
    assert byte_size(encrypted) > byte_size(plaintext)

    assert {:ok, ^plaintext} = Encryption.decrypt(encrypted)
  end

  test "each encryption produces a unique IV" do
    plaintext = "same-value"
    a = Encryption.encrypt(plaintext)
    b = Encryption.encrypt(plaintext)

    # IVs should differ (first 12 bytes)
    assert binary_part(a, 0, 12) != binary_part(b, 0, 12)

    # Both should decrypt to the same value
    assert {:ok, ^plaintext} = Encryption.decrypt(a)
    assert {:ok, ^plaintext} = Encryption.decrypt(b)
  end

  test "tamper detection" do
    encrypted = Encryption.encrypt("secret")

    # Flip a byte in the ciphertext
    <<iv::binary-size(12), tag::binary-size(16), ct::binary>> = encrypted
    tampered_ct = :crypto.exor(ct, <<1>> <> :binary.copy(<<0>>, byte_size(ct) - 1))
    tampered = <<iv::binary, tag::binary, tampered_ct::binary>>

    assert :error = Encryption.decrypt(tampered)
  end

  test "returns error for invalid binary" do
    assert :error = Encryption.decrypt(<<1, 2, 3>>)
    assert :error = Encryption.decrypt("")
  end
end

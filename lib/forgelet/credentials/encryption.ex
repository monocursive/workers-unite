defmodule Forgelet.Credentials.Encryption do
  @moduledoc """
  AES-256-GCM encryption for credential values at rest.

  Key source: `CREDENTIAL_ENCRYPTION_KEY` env var, or derived from
  `secret_key_base` via SHA-256.

  Binary format: `<<iv::96, tag::128, ciphertext::binary>>`
  AAD: `"forgelet_credential"`
  """

  @aad "forgelet_credential"

  @doc """
  Encrypts a plaintext string. Returns a binary blob.
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    key = encryption_key()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>
  end

  @doc """
  Decrypts a binary blob produced by `encrypt/1`. Returns `{:ok, plaintext}` or `:error`.
  """
  def decrypt(<<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>) do
    key = encryption_key()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end

  def decrypt(_), do: :error

  defp encryption_key do
    case Application.get_env(:forgelet, :credential_encryption_key) do
      key when is_binary(key) and byte_size(key) == 32 ->
        key

      _ ->
        secret_key_base =
          Application.get_env(:forgelet, ForgeletWeb.Endpoint)[:secret_key_base] ||
            raise "No credential_encryption_key or secret_key_base configured"

        :crypto.mac(:hmac, :sha256, secret_key_base, "forgelet_credential_encryption")
    end
  end
end

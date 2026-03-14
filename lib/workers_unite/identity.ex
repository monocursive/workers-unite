defmodule WorkersUnite.Identity do
  @moduledoc """
  Cryptographic identity primitives for WorkersUnite agents and nodes.
  Uses Ed25519 for signing and SHA-256 for fingerprinting.
  """

  @doc """
  Generates a new Ed25519 keypair.
  Returns `%{public: <<32 bytes>>, secret: <<32 bytes>>}`.
  """
  def generate do
    {public, secret} = :crypto.generate_key(:eddsa, :ed25519)
    %{public: public, secret: secret}
  end

  @doc """
  Signs data with an Ed25519 secret key.
  Returns a 64-byte signature.
  """
  def sign(data, secret_key) when is_binary(data) and is_binary(secret_key) do
    :crypto.sign(:eddsa, :none, data, [secret_key, :ed25519])
  end

  @doc """
  Verifies an Ed25519 signature against data and a public key.
  Returns a boolean.
  """
  def verify(data, signature, public_key)
      when is_binary(data) and is_binary(signature) and is_binary(public_key) do
    :crypto.verify(:eddsa, :none, data, signature, [public_key, :ed25519])
  end

  @doc """
  Computes a 16-character hex fingerprint of a public key using SHA-256.
  """
  def fingerprint(public_key) when is_binary(public_key) do
    :crypto.hash(:sha256, public_key)
    |> binary_part(0, 8)
    |> Base.encode16(case: :lower)
  end
end

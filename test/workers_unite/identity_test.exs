defmodule WorkersUnite.IdentityTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias WorkersUnite.Identity

  describe "generate/0" do
    test "returns a map with public and secret keys" do
      keypair = Identity.generate()
      assert %{public: public, secret: secret} = keypair
      assert byte_size(public) == 32
      assert byte_size(secret) == 32
    end

    test "generates different keypairs each time" do
      kp1 = Identity.generate()
      kp2 = Identity.generate()
      assert kp1.public != kp2.public
      assert kp1.secret != kp2.secret
    end
  end

  describe "sign/2 and verify/3" do
    test "sign+verify roundtrip succeeds" do
      keypair = Identity.generate()
      data = "hello workers_unite"
      signature = Identity.sign(data, keypair.secret)
      assert byte_size(signature) == 64
      assert Identity.verify(data, signature, keypair.public)
    end

    test "verify rejects tampered data" do
      keypair = Identity.generate()
      signature = Identity.sign("original", keypair.secret)
      refute Identity.verify("tampered", signature, keypair.public)
    end

    test "verify rejects wrong key" do
      kp1 = Identity.generate()
      kp2 = Identity.generate()
      signature = Identity.sign("data", kp1.secret)
      refute Identity.verify("data", signature, kp2.public)
    end

    test "verify rejects tampered signature" do
      keypair = Identity.generate()
      data = "data"
      signature = Identity.sign(data, keypair.secret)
      <<first_byte, rest::binary>> = signature
      tampered = <<bxor(first_byte, 0xFF), rest::binary>>
      refute Identity.verify(data, tampered, keypair.public)
    end
  end

  describe "fingerprint/1" do
    test "is deterministic" do
      keypair = Identity.generate()
      fp1 = Identity.fingerprint(keypair.public)
      fp2 = Identity.fingerprint(keypair.public)
      assert fp1 == fp2
    end

    test "returns a 16-character hex string" do
      keypair = Identity.generate()
      fp = Identity.fingerprint(keypair.public)
      assert String.length(fp) == 16
      assert Regex.match?(~r/^[0-9a-f]{16}$/, fp)
    end

    test "is unique per key" do
      kp1 = Identity.generate()
      kp2 = Identity.generate()
      refute Identity.fingerprint(kp1.public) == Identity.fingerprint(kp2.public)
    end
  end
end

defmodule WorkersUnite.EventTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias WorkersUnite.Event
  alias WorkersUnite.Identity

  setup do
    {:ok, keypair: Identity.generate()}
  end

  describe "new/4" do
    test "creates a valid event that passes verify", %{keypair: kp} do
      assert {:ok, event} = Event.new(:agent_joined, kp, %{name: "bot-1"})
      assert event.kind == :agent_joined
      assert event.author == kp.public
      # Payload keys are normalized to strings
      assert event.payload == %{"name" => "bot-1"}
      assert is_integer(event.timestamp)
      assert byte_size(event.id) == 32
      assert byte_size(event.signature) == 64
      assert event.references == []
      assert event.scope == nil

      assert {:ok, ^event} = Event.verify(event)
    end

    test "rejects an invalid kind", %{keypair: kp} do
      assert {:error, "invalid event kind: :explode"} =
               Event.new(:explode, kp, %{})
    end

    test "accepts optional references and scope", %{keypair: kp} do
      ref_id = :crypto.hash(:sha256, "ref")

      assert {:ok, event} =
               Event.new(:comment_added, kp, %{body: "lgtm"},
                 references: [ref_id],
                 scope: "repo:workers_unite"
               )

      assert event.references == [ref_id]
      assert event.scope == "repo:workers_unite"
      assert {:ok, _} = Event.verify(event)
    end

    test "normalizes atom keys to strings", %{keypair: kp} do
      assert {:ok, event} = Event.new(:agent_joined, kp, %{name: "bot-1", nested: %{key: "val"}})
      assert event.payload == %{"name" => "bot-1", "nested" => %{"key" => "val"}}
    end
  end

  describe "ref/1" do
    test "returns hex-encoded event ID", %{keypair: kp} do
      {:ok, event} = Event.new(:agent_joined, kp, %{})
      ref = Event.ref(event)
      assert is_binary(ref)
      assert String.length(ref) == 64
      assert {:ok, _} = Base.decode16(ref, case: :lower)
    end
  end

  describe "verify/1" do
    test "rejects a tampered payload", %{keypair: kp} do
      {:ok, event} = Event.new(:repo_created, kp, %{name: "my-repo"})
      tampered = %{event | payload: %{"name" => "evil-repo"}}
      assert {:error, "id mismatch"} = Event.verify(tampered)
    end

    test "rejects a tampered id", %{keypair: kp} do
      {:ok, event} = Event.new(:intent_published, kp, %{"title" => "refactor"})
      fake_id = :crypto.hash(:sha256, "fake")
      tampered = %{event | id: fake_id}
      assert {:error, "id mismatch"} = Event.verify(tampered)
    end

    test "rejects a tampered signature", %{keypair: kp} do
      {:ok, event} = Event.new(:vote_cast, kp, %{"proposal_ref" => "abc", "verdict" => "accept"})
      <<first_byte, rest::binary>> = event.signature
      bad_sig = <<bxor(first_byte, 0xFF), rest::binary>>
      tampered = %{event | signature: bad_sig}
      assert {:error, "invalid signature"} = Event.verify(tampered)
    end
  end

  describe "valid_kinds/0" do
    test "returns all expected event kinds including spec additions" do
      kinds = Event.valid_kinds()
      assert length(kinds) == 29

      # Check that core kinds are present
      for kind <- [
            :agent_joined,
            :agent_left,
            :agent_provenance,
            :intent_published,
            :intent_claimed,
            :intent_decomposed,
            :intent_contested,
            :intent_withdrawn,
            :proposal_submitted,
            :proposal_revised,
            :proposal_withdrawn,
            :validation_requested,
            :validation_result,
            :vote_cast,
            :consensus_reached,
            :consensus_failed,
            :merge_executed,
            :merge_rejected,
            :session_completed,
            :session_failed,
            :capability_granted,
            :capability_revoked,
            :repo_created,
            :repo_ref_updated,
            :comment_added,
            :annotation_added
          ] do
        assert kind in kinds, "missing kind: #{kind}"
      end
    end
  end
end

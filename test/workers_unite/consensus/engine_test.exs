defmodule WorkersUnite.Consensus.EngineTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.{EventStore, EventHelpers}
  alias WorkersUnite.Consensus.Engine

  describe "vote evaluation" do
    test "evaluates consensus when votes reach threshold" do
      proposal_ref = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      kp1 = EventHelpers.generate_keypair()
      kp2 = EventHelpers.generate_keypair()

      vote1 = EventHelpers.build_vote_event(proposal_ref, :accept, keypair: kp1)
      vote2 = EventHelpers.build_vote_event(proposal_ref, :accept, keypair: kp2)

      {:ok, _} = EventStore.append(vote1)
      {:ok, _} = EventStore.append(vote2)

      Process.sleep(200)

      {:ok, result} = Engine.evaluate(proposal_ref)
      assert result == :accepted
    end

    test "set_policy overrides for specific scope" do
      proposal_ref = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      Engine.set_policy(proposal_ref, {:unanimous, 3})

      kp = EventHelpers.generate_keypair()
      vote = EventHelpers.build_vote_event(proposal_ref, :accept, keypair: kp)
      {:ok, _} = EventStore.append(vote)

      Process.sleep(100)

      {:ok, result} = Engine.evaluate(proposal_ref)
      assert result == :pending
    end
  end
end

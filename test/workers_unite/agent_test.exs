defmodule WorkersUnite.AgentTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.{Agent, EventStore, Identity, Repository, Event}

  describe "spawn/2" do
    test "starts process and publishes events" do
      {:ok, pid, public_key} = Agent.spawn(:coder)

      assert Process.alive?(pid)

      # Allow async :publish_joined to fire
      Process.sleep(100)

      joined_events = EventStore.by_kind(:agent_joined)
      assert Enum.any?(joined_events, &(&1.author == public_key))

      provenance_events = EventStore.by_kind(:agent_provenance)
      assert Enum.any?(provenance_events, &(&1.author == public_key))
    end

    test "accepts provenance options" do
      {:ok, _pid, public_key} =
        Agent.spawn(:coder,
          model: "claude-sonnet-4",
          model_version: "20250514",
          capabilities: ["elixir", "rust"]
        )

      Process.sleep(100)

      state = Agent.inspect_state(public_key)
      assert state.model == "claude-sonnet-4"
      assert state.model_version == "20250514"
    end
  end

  describe "inspect_state/1" do
    test "returns sanitized state without secret key" do
      {:ok, _pid, public_key} = Agent.spawn(:reviewer)

      Process.sleep(100)

      state = Agent.inspect_state(public_key)

      assert state.keypair == %{public: public_key}
      refute Map.has_key?(state.keypair, :secret)
      assert state.kind == :reviewer
      assert state.status == :idle
      assert state.reputation == 0.5
    end
  end

  describe "claim_intent/3" do
    test "publishes intent_claimed event and returns ref" do
      {:ok, _pid, public_key} = Agent.spawn(:coder)
      owner = Identity.generate()
      {:ok, _repo_pid, repo_id} = Repository.create("claim-repo", owner)

      Process.sleep(100)

      {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Claim me"})
      fake_ref = Event.ref(intent_event)
      assert {:ok, _event_ref} = Agent.claim_intent(public_key, repo_id, fake_ref)

      Process.sleep(100)

      claimed_events = EventStore.by_kind(:intent_claimed)

      assert Enum.any?(claimed_events, fn e ->
               e.author == public_key and e.payload["intent_ref"] == fake_ref
             end)
    end

    test "sets scope when provided" do
      {:ok, _pid, public_key} = Agent.spawn(:coder)
      owner = Identity.generate()
      {:ok, _repo_pid, repo_id} = Repository.create("claim-scope-repo", owner)
      scope = {:repo, repo_id}

      Process.sleep(100)

      {:ok, intent_event} =
        Repository.publish_intent(repo_id, owner, %{"title" => "Scoped claim"})

      fake_ref = Event.ref(intent_event)
      assert {:ok, _event_ref} = Agent.claim_intent(public_key, fake_ref, scope)

      Process.sleep(100)

      claimed_events = EventStore.by_kind(:intent_claimed)
      event = Enum.find(claimed_events, &(&1.author == public_key))
      assert event.scope == scope
    end

    test "rejects duplicate claims for the same repo intent" do
      owner = Identity.generate()
      {:ok, _repo_pid, repo_id} = Repository.create("duplicate-claim-repo", owner)
      {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Only once"})
      intent_ref = Event.ref(intent_event)
      {:ok, _pid1, pk1} = Agent.spawn(:coder)
      {:ok, _pid2, pk2} = Agent.spawn(:coder)

      Process.sleep(100)

      assert {:ok, _event_ref} = Agent.claim_intent(pk1, repo_id, intent_ref)
      assert {:error, :already_claimed} = Agent.claim_intent(pk2, repo_id, intent_ref)
    end
  end

  describe "vote/4" do
    test "publishes vote_cast event with confidence" do
      {:ok, _pid, public_key} = Agent.spawn(:reviewer)

      Process.sleep(100)

      fake_proposal = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      assert {:ok, _ref} = Agent.vote(public_key, fake_proposal, :accept, confidence: 0.9)

      Process.sleep(100)

      vote_events = EventStore.by_kind(:vote_cast)

      assert Enum.any?(vote_events, fn e ->
               e.author == public_key and
                 e.payload["proposal_ref"] == fake_proposal and
                 e.payload["verdict"] == "accept" and
                 e.payload["confidence"] == 0.9
             end)
    end
  end

  describe "list_local/0" do
    test "returns spawned agents" do
      {:ok, _pid1, pk1} = Agent.spawn(:coder)
      {:ok, _pid2, pk2} = Agent.spawn(:reviewer)

      Process.sleep(100)

      agents = Agent.list_local()
      agent_ids = Enum.map(agents, fn {id, _pid} -> id end)

      assert pk1 in agent_ids
      assert pk2 in agent_ids
    end
  end
end

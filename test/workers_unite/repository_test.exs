defmodule WorkersUnite.RepositoryTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.{Agent, Event, EventStore, Git, Identity, Repository}
  alias WorkersUnite.Agent.Workspace

  setup do
    owner = Identity.generate()
    %{owner: owner}
  end

  describe "create/3" do
    test "starts process and publishes repo_created", %{owner: owner} do
      assert {:ok, pid, repo_id} = Repository.create("test-repo", owner)
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert byte_size(repo_id) == 32

      # Allow the async :publish_created message to be processed
      Process.sleep(100)

      events = EventStore.by_kind(:repo_created)
      scoped = Enum.filter(events, fn e -> e.scope == {:repo, repo_id} end)
      assert length(scoped) >= 1

      event = hd(scoped)
      assert event.kind == :repo_created
      assert event.author == owner.public
      assert event.payload["name"] || event.payload[:name]
    end
  end

  describe "get_state/1" do
    test "returns state with name and id", %{owner: owner} do
      {:ok, _pid, repo_id} = Repository.create("state-repo", owner)
      Process.sleep(100)

      state = Repository.get_state(repo_id)
      assert state.name == "state-repo"
      assert state.id == repo_id
      # Owner secret key should be stripped from returned state
      refute Map.has_key?(state.owner, :secret)
      assert state.owner.public == owner.public
    end
  end

  describe "publish_intent/3" do
    test "creates scoped event", %{owner: owner} do
      {:ok, _pid, repo_id} = Repository.create("intent-repo", owner)
      Process.sleep(100)

      agent = Identity.generate()
      payload = %{"title" => "Refactor auth", "description" => "Clean up auth module"}
      assert {:ok, event} = Repository.publish_intent(repo_id, agent, payload)

      Process.sleep(100)

      assert event.kind == :intent_published
      assert event.scope == {:repo, repo_id}
      assert event.author == agent.public

      events = EventStore.by_scope({:repo, repo_id})
      intent_events = Enum.filter(events, fn e -> e.kind == :intent_published end)
      assert length(intent_events) >= 1
    end
  end

  describe "list_local/0" do
    test "returns created repos", %{owner: owner} do
      {:ok, _pid1, repo_id1} = Repository.create("list-repo-1", owner)
      {:ok, _pid2, repo_id2} = Repository.create("list-repo-2", owner)
      Process.sleep(100)

      repos = Repository.list_local()
      repo_ids = Enum.map(repos, & &1.repo_id)

      assert repo_id1 in repo_ids
      assert repo_id2 in repo_ids
    end
  end

  describe "merge execution" do
    test "accepted branch proposal updates main and emits repo_ref_updated", %{owner: owner} do
      {:ok, _repo_pid, repo_id} = Repository.create("merge-repo", owner)
      {:ok, _coder_pid, coder_id} = Agent.spawn(:coder)
      repo_hex = Base.encode16(repo_id, case: :lower)

      Process.sleep(100)

      {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Merge me"})
      intent_ref = Event.ref(intent_event)
      assert {:ok, _claim_ref} = Agent.claim_intent(coder_id, repo_id, intent_ref)

      {:ok, session_root} = Workspace.create_session_root()

      artifact =
        try do
          {:ok, checkout} =
            Workspace.prepare_task_checkout(session_root, repo_id, coder_id, intent_ref)

          File.write!(Path.join(checkout.repo_path, "MERGE_TEST.md"), "merged\n")
          {:ok, _commit_sha} = Git.commit_all(checkout.repo_path, "Add merge test file")
          :ok = Git.push_branch(checkout.repo_path, checkout.branch_name)
          {:ok, head_sha} = Git.rev_parse(checkout.repo_path, "HEAD")
          %{"type" => "branch", "name" => checkout.branch_name, "head" => head_sha}
        after
          Workspace.cleanup(session_root)
        end

      {:ok, proposal_ref} =
        Agent.submit_proposal(
          coder_id,
          %{
            "intent_ref" => intent_ref,
            "repo_id" => repo_hex,
            "summary" => "Merge branch artifact",
            "confidence" => 0.9,
            "affected_files" => ["MERGE_TEST.md"],
            "artifact" => artifact
          },
          {:repo, repo_id}
        )

      consensus_author = Identity.generate()

      {:ok, consensus_event} =
        Event.new(
          :consensus_reached,
          consensus_author,
          %{"proposal_ref" => proposal_ref, "outcome" => "accepted"},
          scope: {:repo, repo_id}
        )

      assert {:ok, _stored} = EventStore.append(consensus_event)
      Process.sleep(200)

      assert Enum.any?(
               EventStore.by_kind(:merge_executed),
               &(&1.payload["proposal_ref"] == proposal_ref)
             )

      repo_ref_event =
        Enum.find(
          EventStore.by_kind(:repo_ref_updated),
          &(&1.payload["proposal_ref"] == proposal_ref)
        )

      assert repo_ref_event
      assert repo_ref_event.payload["branch"] == "main"

      verify_dir =
        Path.join(
          System.tmp_dir!(),
          "workers-unite-verify-#{System.unique_integer([:positive, :monotonic])}"
        )

      File.mkdir_p!(verify_dir)

      try do
        assert :ok = Git.clone(Repository.get_state(repo_id).path, verify_dir)
        assert File.exists?(Path.join(verify_dir, "MERGE_TEST.md"))
      after
        File.rm_rf(verify_dir)
      end
    end
  end
end

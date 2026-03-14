defmodule WorkersUnite.Agent.Runtime.OpenCodeTest do
  use WorkersUnite.DataCase, async: false

  alias WorkersUnite.{Agent, Credentials, Identity, Repository, Event}
  alias WorkersUnite.Agent.Runtime.OpenCode

  @mock_cli_path Path.expand("../../../support/mock_opencode.sh", __DIR__)

  setup do
    original_path = Application.get_env(:workers_unite, :opencode_cli_path)
    Application.put_env(:workers_unite, :opencode_cli_path, @mock_cli_path)

    on_exit(fn ->
      if original_path do
        Application.put_env(:workers_unite, :opencode_cli_path, original_path)
      else
        Application.delete_env(:workers_unite, :opencode_cli_path)
      end
    end)

    Credentials.upsert("anthropic", "ANTHROPIC_API_KEY", "test-key", nil)
    WorkersUnite.CredentialStore.reload(caller: self())

    :ok
  end

  describe "start_run/3" do
    test "starts a session and returns pid and token" do
      {:ok, _pid, agent_id} = Agent.spawn(:coder)
      owner = Identity.generate()
      {:ok, _repo_pid, repo_id} = Repository.create("test-repo", owner)

      Process.sleep(100)

      {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Task"})
      intent_ref = Event.ref(intent_event)
      {:ok, _claim_ref} = Agent.claim_intent(agent_id, repo_id, intent_ref)

      assert {:ok, session_pid, token} =
               OpenCode.start_run(self(), agent_id, :coder, timeout_ms: 1_000)

      assert is_pid(session_pid)
      assert is_binary(token)

      ref = Process.monitor(session_pid)
      assert_receive {:DOWN, ^ref, :process, ^session_pid, _reason}, 2_000
    end

    test "captures multi-chunk output correctly" do
      {:ok, _pid, agent_id} = Agent.spawn(:coder)
      owner = Identity.generate()
      {:ok, _repo_pid, repo_id} = Repository.create("multi-chunk-repo", owner)

      Process.sleep(100)

      {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Task"})
      intent_ref = Event.ref(intent_event)
      {:ok, _claim_ref} = Agent.claim_intent(agent_id, repo_id, intent_ref)

      assert {:ok, session_pid, _token} =
               OpenCode.start_run(self(), agent_id, :coder,
                 timeout_ms: 2_000,
                 env: [{"MOCK_OPENCODE_SCENARIO", "multi_chunk"}]
               )

      assert_receive {:session_ended, ^session_pid, :completed, output}, 3_000
      assert is_binary(output)
    end
  end

  describe "cancel_run/1" do
    test "terminates a running session" do
      {:ok, _pid, agent_id} = Agent.spawn(:coder)
      owner = Identity.generate()
      {:ok, _repo_pid, repo_id} = Repository.create("cancel-repo", owner)

      Process.sleep(100)

      {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Task"})
      intent_ref = Event.ref(intent_event)
      {:ok, _claim_ref} = Agent.claim_intent(agent_id, repo_id, intent_ref)

      assert {:ok, session_pid, _token} =
               OpenCode.start_run(self(), agent_id, :coder,
                 timeout_ms: 60_000,
                 env: [{"MOCK_OPENCODE_SCENARIO", "timeout"}]
               )

      Process.sleep(50)
      assert :ok = OpenCode.cancel_run(session_pid)
    end
  end

  describe "capabilities/0" do
    test "returns CLI runtime capabilities" do
      caps = OpenCode.capabilities()
      assert caps.mode == :cli
      assert :mcp in caps.tools
      assert :filesystem in caps.tools
      assert :shell in caps.tools
    end
  end
end

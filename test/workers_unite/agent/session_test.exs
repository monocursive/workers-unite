defmodule WorkersUnite.Agent.SessionTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.{Agent, Credentials, Event, Identity, Repository}

  test "coder session requires an active task" do
    {:ok, _pid, agent_id} = Agent.spawn(:coder)

    assert {:error, :no_active_task} = Agent.start_session(agent_id, timeout_ms: 1_000)
  end

  test "starts and cleans up a mock OpenCode session for a claimed intent" do
    Credentials.upsert("anthropic", "ANTHROPIC_API_KEY", "test-key", nil)
    WorkersUnite.CredentialStore.reload(caller: self())

    {:ok, _pid, agent_id} = Agent.spawn(:coder)
    owner = Identity.generate()
    {:ok, _repo_pid, repo_id} = Repository.create("session-repo", owner)

    Process.sleep(100)

    {:ok, intent_event} = Repository.publish_intent(repo_id, owner, %{"title" => "Session task"})
    intent_ref = Event.ref(intent_event)

    assert {:ok, _claim_ref} = Agent.claim_intent(agent_id, repo_id, intent_ref)

    assert {:ok, session_pid, token} = Agent.start_session(agent_id, timeout_ms: 1_000)
    assert is_pid(session_pid)
    assert is_binary(token)

    ref = Process.monitor(session_pid)
    assert_receive {:DOWN, ^ref, :process, ^session_pid, _reason}, 2_000

    state = Agent.inspect_state(agent_id)
    assert state.active_session == nil
    assert state.last_session_status == :completed
  end
end

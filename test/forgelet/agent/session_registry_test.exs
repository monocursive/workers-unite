defmodule Forgelet.Agent.SessionRegistryTest do
  use ExUnit.Case, async: false

  alias Forgelet.Agent.SessionRegistry

  test "creates, looks up, and invalidates a token" do
    agent_id = :crypto.strong_rand_bytes(32)
    {:ok, token} = SessionRegistry.create(agent_id, :coder, "/tmp/workspace")

    assert {:ok, session} = SessionRegistry.lookup(token)
    assert session.agent_id == agent_id
    assert session.kind == :coder
    assert session.working_dir == "/tmp/workspace"
    assert session.owner_user_id == nil

    assert :ok = SessionRegistry.invalidate(token)
    assert :error = SessionRegistry.lookup(token)
  end

  test "creates session with owner_user_id" do
    agent_id = :crypto.strong_rand_bytes(32)
    user_id = Ecto.UUID.generate()
    {:ok, token} = SessionRegistry.create(agent_id, :coder, "/tmp/workspace", user_id)

    assert {:ok, session} = SessionRegistry.lookup(token)
    assert session.owner_user_id == user_id
  end

  test "list_for_user filters by owner_user_id" do
    agent_id = :crypto.strong_rand_bytes(32)
    user_a = Ecto.UUID.generate()
    user_b = Ecto.UUID.generate()

    {:ok, _token_a} = SessionRegistry.create(agent_id, :coder, "/tmp/a", user_a)
    {:ok, _token_b} = SessionRegistry.create(agent_id, :coder, "/tmp/b", user_b)

    sessions_a = SessionRegistry.list_for_user(user_a)
    assert length(sessions_a) == 1
    assert hd(sessions_a).owner_user_id == user_a
  end
end

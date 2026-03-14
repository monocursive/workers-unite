defmodule WorkersUnite.EventStoreTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.{EventStore, EventHelpers}

  setup do
    table = :"test_events_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = EventStore.start_link(name: :"store_#{table}", table: table)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{store: :"store_#{table}", table: table}
  end

  describe "append/2 and get/2" do
    test "stores and retrieves an event", %{store: store, table: table} do
      event = EventHelpers.build_event(:agent_joined)
      assert {:ok, ^event} = EventStore.append(event, store)
      assert {:ok, ^event} = EventStore.get(event.id, table)
    end

    test "rejects invalid signature", %{store: store} do
      event = EventHelpers.build_event(:agent_joined)
      tampered = %{event | signature: :crypto.strong_rand_bytes(64)}
      assert {:error, _} = EventStore.append(tampered, store)
    end

    test "rejects duplicate id", %{store: store} do
      event = EventHelpers.build_event(:agent_joined)
      assert {:ok, _} = EventStore.append(event, store)
      assert {:error, :duplicate} = EventStore.append(event, store)
    end
  end

  describe "query functions" do
    test "by_kind filters correctly", %{store: store, table: table} do
      kp = EventHelpers.generate_keypair()
      e1 = EventHelpers.build_event(:agent_joined, keypair: kp)
      e2 = EventHelpers.build_event(:repo_created, keypair: kp)
      EventStore.append(e1, store)
      EventStore.append(e2, store)

      joined = EventStore.by_kind(:agent_joined, table)
      assert length(joined) == 1
      assert hd(joined).kind == :agent_joined
    end

    test "by_author filters correctly", %{store: store, table: table} do
      kp1 = EventHelpers.generate_keypair()
      kp2 = EventHelpers.generate_keypair()
      e1 = EventHelpers.build_event(:agent_joined, keypair: kp1)
      e2 = EventHelpers.build_event(:agent_joined, keypair: kp2)
      EventStore.append(e1, store)
      EventStore.append(e2, store)

      events = EventStore.by_author(kp1.public, table)
      assert length(events) == 1
      assert hd(events).author == kp1.public
    end

    test "by_scope filters correctly", %{store: store, table: table} do
      scope = {:repo, :crypto.strong_rand_bytes(32)}

      e1 =
        EventHelpers.build_event(:intent_published,
          payload: %{"title" => "test"},
          event_opts: [scope: scope]
        )

      e2 = EventHelpers.build_event(:agent_joined)
      EventStore.append(e1, store)
      EventStore.append(e2, store)

      scoped = EventStore.by_scope(scope, table)
      assert length(scoped) == 1
    end

    test "count returns correct value", %{store: store, table: table} do
      assert EventStore.count(table) == 0
      EventStore.append(EventHelpers.build_event(:agent_joined), store)
      assert EventStore.count(table) == 1
      EventStore.append(EventHelpers.build_event(:repo_created), store)
      assert EventStore.count(table) == 2
    end
  end

  describe "PubSub broadcasts" do
    test "broadcasts on append", %{store: store} do
      Phoenix.PubSub.subscribe(WorkersUnite.PubSub, "events")
      event = EventHelpers.build_event(:agent_joined)
      EventStore.append(event, store)
      assert_receive {:event, ^event}, 1000
    end

    test "broadcasts on kind topic", %{store: store} do
      Phoenix.PubSub.subscribe(WorkersUnite.PubSub, "events:kind:agent_joined")
      event = EventHelpers.build_event(:agent_joined)
      EventStore.append(event, store)
      assert_receive {:event, ^event}, 1000
    end
  end
end

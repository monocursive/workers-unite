defmodule WorkersUnite.DemoTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.EventStore

  test "run/0 completes the full demo workflow" do
    assert :ok = WorkersUnite.Demo.run()

    # Verify key events were created
    assert length(EventStore.by_kind(:repo_created)) >= 1
    assert length(EventStore.by_kind(:agent_joined)) >= 3
    assert length(EventStore.by_kind(:agent_provenance)) >= 3
    assert length(EventStore.by_kind(:intent_published)) >= 1
    assert length(EventStore.by_kind(:intent_claimed)) >= 1
    assert length(EventStore.by_kind(:proposal_submitted)) >= 1
    assert length(EventStore.by_kind(:vote_cast)) >= 2

    # Verify the full pipeline completes: consensus + merge
    assert length(EventStore.by_kind(:consensus_reached)) >= 1
    assert length(EventStore.by_kind(:merge_executed)) >= 1

    # Total events should be substantial
    assert EventStore.count() >= 10
  end
end

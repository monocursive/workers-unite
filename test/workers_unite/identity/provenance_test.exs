defmodule WorkersUnite.Identity.ProvenanceTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Identity.Provenance

  describe "new/1" do
    test "creates a provenance struct with a valid kind" do
      attrs = [
        agent_id: "agent-001",
        kind: :coder,
        created_at: System.os_time(:millisecond)
      ]

      assert {:ok, %Provenance{} = prov} = Provenance.new(attrs)
      assert prov.agent_id == "agent-001"
      assert prov.kind == :coder
      assert prov.spawner == nil
      assert prov.capabilities == []
      assert prov.metadata == %{}
    end

    test "accepts all valid kinds" do
      for kind <- Provenance.valid_kinds() do
        attrs = [
          agent_id: "agent-#{kind}",
          kind: kind,
          created_at: System.os_time(:millisecond)
        ]

        assert {:ok, %Provenance{kind: ^kind}} = Provenance.new(attrs)
      end
    end

    test "rejects an invalid kind" do
      attrs = [
        agent_id: "agent-bad",
        kind: :hacker,
        created_at: System.os_time(:millisecond)
      ]

      assert {:error, "invalid kind: :hacker"} = Provenance.new(attrs)
    end

    test "returns error when enforced keys are missing" do
      assert {:error, _reason} = Provenance.new(%{kind: :coder})
    end

    test "accepts a map of attributes" do
      attrs = %{
        agent_id: "agent-map",
        kind: :reviewer,
        created_at: System.os_time(:millisecond),
        model: "claude-opus-4-6",
        capabilities: [:read, :write]
      }

      assert {:ok, %Provenance{} = prov} = Provenance.new(attrs)
      assert prov.model == "claude-opus-4-6"
      assert prov.capabilities == [:read, :write]
    end
  end
end

defmodule WorkersUnite.Schema.ProposalTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Schema

  describe "proposal_submitted" do
    test "valid event passes" do
      event = %{
        kind: :proposal_submitted,
        payload: %{
          "intent_ref" => "intent_abc",
          "repo_id" => "repo_123",
          "summary" => "Update the federation flow",
          "confidence" => 0.8,
          "affected_files" => ["lib/workers_unite/federation.ex"],
          "artifact" => %{"type" => "commit_range", "from" => "aaa111", "to" => "bbb222"}
        }
      }

      assert :ok = Schema.validate(event)
    end

    test "missing intent_ref fails" do
      event = %{
        kind: :proposal_submitted,
        payload: %{
          "repo_id" => "repo_123",
          "summary" => "Update the federation flow",
          "confidence" => 0.8,
          "affected_files" => ["lib/workers_unite/federation.ex"],
          "artifact" => %{"type" => "commit_range", "from" => "aaa111", "to" => "bbb222"}
        }
      }

      assert {:error, "missing required fields: intent_ref"} = Schema.validate(event)
    end

    test "missing artifact fails" do
      event = %{
        kind: :proposal_submitted,
        payload: %{
          "intent_ref" => "intent_abc",
          "repo_id" => "repo_123",
          "summary" => "Update the federation flow",
          "confidence" => 0.8,
          "affected_files" => ["lib/workers_unite/federation.ex"]
        }
      }

      assert {:error, "missing required fields: artifact"} = Schema.validate(event)
    end

    test "malformed commit_range artifact fails" do
      event = %{
        kind: :proposal_submitted,
        payload: %{
          "intent_ref" => "intent_abc",
          "repo_id" => "repo_123",
          "summary" => "Update the federation flow",
          "confidence" => 0.8,
          "affected_files" => ["lib/workers_unite/federation.ex"],
          "artifact" => %{"type" => "commit_range", "from" => "aaa111"}
        }
      }

      assert {:error, _reason} = Schema.validate(event)
    end

    test "branch artifact passes" do
      event = %{
        kind: :proposal_submitted,
        payload: %{
          "intent_ref" => "intent_abc",
          "repo_id" => "repo_123",
          "summary" => "Update the federation flow",
          "confidence" => 0.8,
          "affected_files" => ["lib/workers_unite/federation.ex"],
          "artifact" => %{"type" => "branch", "name" => "agent/demo", "head" => "bbb222"}
        }
      }

      assert :ok = Schema.validate(event)
    end

    test "patch artifact passes" do
      event = %{
        kind: :proposal_submitted,
        payload: %{
          "intent_ref" => "intent_abc",
          "repo_id" => "repo_123",
          "summary" => "Update the federation flow",
          "confidence" => 0.8,
          "affected_files" => ["lib/workers_unite/federation.ex"],
          "artifact" => %{
            "type" => "patch",
            "base" => "aaa111",
            "diff" => "diff --git a/foo b/foo"
          }
        }
      }

      assert :ok = Schema.validate(event)
    end
  end

  describe "proposal_updated" do
    test "valid event passes" do
      event = %{
        kind: :proposal_updated,
        payload: %{"intent_ref" => "intent_abc", "proposal_ref" => "prop_123"}
      }

      assert :ok = Schema.validate(event)
    end

    test "missing intent_ref fails" do
      event = %{
        kind: :proposal_updated,
        payload: %{"proposal_ref" => "prop_123"}
      }

      assert {:error, "missing required field: intent_ref"} = Schema.validate(event)
    end

    test "missing proposal_ref fails" do
      event = %{
        kind: :proposal_updated,
        payload: %{"intent_ref" => "intent_abc"}
      }

      assert {:error, "missing required field: proposal_ref"} = Schema.validate(event)
    end
  end

  describe "proposal_withdrawn" do
    test "valid event passes" do
      event = %{
        kind: :proposal_withdrawn,
        payload: %{"intent_ref" => "intent_abc", "proposal_ref" => "prop_123"}
      }

      assert :ok = Schema.validate(event)
    end

    test "missing proposal_ref fails" do
      event = %{
        kind: :proposal_withdrawn,
        payload: %{"intent_ref" => "intent_abc"}
      }

      assert {:error, "missing required field: proposal_ref"} = Schema.validate(event)
    end
  end
end

defmodule WorkersUnite.Schema.IntentTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Schema

  describe "intent_published" do
    test "valid event passes" do
      event = %{kind: :intent_published, payload: %{"title" => "Fix bug"}}
      assert :ok = Schema.validate(event)
    end

    test "missing title fails" do
      event = %{kind: :intent_published, payload: %{}}
      assert {:error, "missing required field: title"} = Schema.validate(event)
    end

    test "empty title fails" do
      event = %{kind: :intent_published, payload: %{"title" => ""}}
      assert {:error, "title must be a non-empty string"} = Schema.validate(event)
    end

    test "valid event with optional fields passes" do
      event = %{
        kind: :intent_published,
        payload: %{
          "title" => "Fix bug",
          "description" => "Detailed description",
          "constraints" => "Must pass tests",
          "affected_paths" => ["lib/foo.ex"],
          "priority" => 0.8,
          "decomposable" => true,
          "tags" => ["bugfix"]
        }
      }

      assert :ok = Schema.validate(event)
    end
  end

  describe "intent_claimed" do
    test "valid event passes" do
      event = %{kind: :intent_claimed, payload: %{"intent_ref" => "abc123"}}
      assert :ok = Schema.validate(event)
    end

    test "missing intent_ref fails" do
      event = %{kind: :intent_claimed, payload: %{}}
      assert {:error, "missing required field: intent_ref"} = Schema.validate(event)
    end
  end

  describe "intent_updated" do
    test "valid event passes" do
      event = %{kind: :intent_updated, payload: %{"intent_ref" => "abc123"}}
      assert :ok = Schema.validate(event)
    end

    test "missing intent_ref fails" do
      event = %{kind: :intent_updated, payload: %{}}
      assert {:error, "missing required field: intent_ref"} = Schema.validate(event)
    end
  end

  describe "intent_cancelled" do
    test "valid event passes" do
      event = %{kind: :intent_cancelled, payload: %{"intent_ref" => "abc123"}}
      assert :ok = Schema.validate(event)
    end

    test "missing intent_ref fails" do
      event = %{kind: :intent_cancelled, payload: %{}}
      assert {:error, "missing required field: intent_ref"} = Schema.validate(event)
    end
  end
end

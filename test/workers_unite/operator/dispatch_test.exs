defmodule WorkersUnite.Operator.DispatchTest do
  use ExUnit.Case, async: true

  alias WorkersUnite.Operator.Dispatch

  describe "find_idle/1" do
    test "rejects invalid string kind" do
      assert {:error, :invalid_kind} = Dispatch.find_idle("invalid")
    end

    test "rejects unknown string kind" do
      assert {:error, :invalid_kind} = Dispatch.find_idle("hacker")
    end

    test "rejects invalid atom kind" do
      assert {:error, :invalid_kind} = Dispatch.find_idle(:hacker)
    end

    test "rejects non-string non-atom kind" do
      assert {:error, :invalid_kind} = Dispatch.find_idle(42)
    end
  end

  describe "spawn_worker/2" do
    test "rejects invalid string kind" do
      assert {:error, :invalid_kind} = Dispatch.spawn_worker("invalid", [])
    end

    test "rejects unknown atom kind" do
      assert {:error, :invalid_kind} = Dispatch.spawn_worker(:hacker, [])
    end
  end

  describe "find_or_spawn/2" do
    test "rejects invalid string kind" do
      assert {:error, :invalid_kind} = Dispatch.find_or_spawn("bad_kind")
    end

    test "rejects invalid atom kind" do
      assert {:error, :invalid_kind} = Dispatch.find_or_spawn(:bad_kind)
    end
  end
end

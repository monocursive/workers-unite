defmodule Forgelet.ModelRegistryTest do
  use ExUnit.Case, async: true

  alias Forgelet.ModelRegistry

  test "resolves logical agent profiles to runtime and model ids" do
    original_registry = Application.get_env(:forgelet, :runtime_registry)
    original_profiles = Application.get_env(:forgelet, :agent_profiles)

    on_exit(fn ->
      Application.put_env(:forgelet, :runtime_registry, original_registry)
      Application.put_env(:forgelet, :agent_profiles, original_profiles)
    end)

    Application.put_env(:forgelet, :runtime_registry, %{
      claude_code: %{
        adapter: Forgelet.Agent.Runtime.ClaudeCode,
        credentials: %{},
        models: %{fast_coder: %{id: "claude-sonnet-4-6"}},
        native_tools: %{coder: ["Read", "Write"]}
      }
    })

    Application.put_env(:forgelet, :agent_profiles, %{
      coder: %{runtime: :claude_code, model: :fast_coder}
    })

    profile = ModelRegistry.resolve_agent_profile(:coder)

    assert profile.runtime == :claude_code
    assert profile.adapter == Forgelet.Agent.Runtime.ClaudeCode
    assert profile.model_id == "claude-sonnet-4-6"
    assert profile.tools == ["Read", "Write"]
  end
end

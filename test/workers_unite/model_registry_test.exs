defmodule WorkersUnite.ModelRegistryTest do
  use WorkersUnite.DataCase, async: false

  alias WorkersUnite.ModelRegistry

  test "resolves agent profiles to opencode runtime and model from catalog" do
    original_registry = Application.get_env(:workers_unite, :runtime_registry)
    original_catalog = Application.get_env(:workers_unite, :opencode_model_catalog)

    on_exit(fn ->
      Application.put_env(:workers_unite, :runtime_registry, original_registry)
      Application.put_env(:workers_unite, :opencode_model_catalog, original_catalog)
    end)

    Application.put_env(:workers_unite, :runtime_registry, %{
      opencode: %{
        adapter: WorkersUnite.Agent.Runtime.OpenCode,
        credentials: %{},
        native_tools: %{coder: ["Read", "Write"]}
      }
    })

    Application.put_env(:workers_unite, :opencode_model_catalog, [
      %{key: "test-model", label: "Test Model", provider: :anthropic, model_id: "test-model-id"}
    ])

    profile = ModelRegistry.resolve_agent_profile(:coder)

    assert profile.runtime == :opencode
    assert profile.adapter == WorkersUnite.Agent.Runtime.OpenCode
    assert profile.model_id == "test-model-id"
    assert profile.provider == :anthropic
    assert profile.tools == ["Read", "Write"]
  end

  test "uses first catalog entry when no default model is set" do
    original_registry = Application.get_env(:workers_unite, :runtime_registry)
    original_catalog = Application.get_env(:workers_unite, :opencode_model_catalog)

    on_exit(fn ->
      Application.put_env(:workers_unite, :runtime_registry, original_registry)
      Application.put_env(:workers_unite, :opencode_model_catalog, original_catalog)
    end)

    Application.put_env(:workers_unite, :runtime_registry, %{
      opencode: %{
        adapter: WorkersUnite.Agent.Runtime.OpenCode,
        credentials: %{},
        native_tools: %{coder: []}
      }
    })

    Application.put_env(:workers_unite, :opencode_model_catalog, [
      %{key: "first-model", label: "First", provider: :openai, model_id: "first-id"},
      %{key: "second-model", label: "Second", provider: :anthropic, model_id: "second-id"}
    ])

    {model_id, provider} = ModelRegistry.resolve_model_from_catalog()

    assert model_id == "first-id"
    assert provider == :openai
  end
end

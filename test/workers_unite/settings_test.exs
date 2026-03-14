defmodule WorkersUnite.SettingsTest do
  use WorkersUnite.DataCase

  alias WorkersUnite.Settings

  setup do
    WorkersUnite.CredentialStore.reload(caller: self())
    user = WorkersUnite.AccountsFixtures.user_fixture()
    {:ok, user: user}
  end

  test "get creates singleton if missing" do
    settings = Settings.get()
    assert settings.id
    assert settings.master_plan_personality == nil
  end

  test "get returns existing singleton" do
    s1 = Settings.get()
    s2 = Settings.get()
    assert s1.id == s2.id
  end

  test "update modifies settings" do
    {:ok, settings} = Settings.update(%{master_plan_personality: "Be thorough."})
    assert settings.master_plan_personality == "Be thorough."
  end

  test "get_personality returns personality text" do
    Settings.update(%{master_plan_personality: "Focus on tests."})
    assert Settings.get_personality() == "Focus on tests."
  end

  test "get_personality returns nil when not set" do
    assert Settings.get_personality() == nil
  end

  test "onboarding_completed? returns false initially" do
    refute Settings.onboarding_completed?()
  end

  test "complete_onboarding marks onboarding as done" do
    refute Settings.onboarding_completed?()
    Settings.complete_onboarding(nil)
    assert Settings.onboarding_completed?()
  end

  describe "default agent model" do
    test "get_default_agent_model returns nil initially" do
      assert Settings.get_default_agent_model() == nil
    end

    test "set_default_agent_model sets a valid model key", %{user: user} do
      {:ok, settings} = Settings.set_default_agent_model("claude-sonnet-4", user.id)
      assert settings.default_agent_model == "claude-sonnet-4"
      assert Settings.get_default_agent_model() == "claude-sonnet-4"
    end

    test "set_default_agent_model rejects invalid model key", %{user: user} do
      assert {:error, :invalid_model_key} =
               Settings.set_default_agent_model("nonexistent-model", user.id)
    end

    test "set_default_agent_model allows nil to clear", %{user: user} do
      Settings.set_default_agent_model("claude-sonnet-4", user.id)
      {:ok, _} = Settings.set_default_agent_model(nil, user.id)
      assert Settings.get_default_agent_model() == nil
    end
  end

  describe "model catalog" do
    test "model_catalog returns list of models" do
      catalog = Settings.model_catalog()
      assert is_list(catalog)
      assert length(catalog) > 0
    end

    test "get_model_entry finds model by key" do
      entry = Settings.get_model_entry("claude-sonnet-4")
      assert entry.label == "Claude Sonnet 4"
      assert entry.provider == :anthropic
    end

    test "get_model_entry returns nil for unknown key" do
      assert Settings.get_model_entry("unknown-model") == nil
    end
  end

  describe "provider configuration" do
    test "provider_configured? returns false when no credentials" do
      refute Settings.provider_configured?(:anthropic)
    end

    test "provider_configured? returns true when credentials exist" do
      WorkersUnite.Credentials.upsert("anthropic", "ANTHROPIC_API_KEY", "test-key", nil)
      WorkersUnite.CredentialStore.reload(caller: self())
      assert Settings.provider_configured?(:anthropic)
    end
  end
end

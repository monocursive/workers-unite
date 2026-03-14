defmodule Forgelet.SettingsTest do
  use Forgelet.DataCase

  alias Forgelet.Settings

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
end

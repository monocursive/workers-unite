defmodule Forgelet.Settings do
  @moduledoc """
  Context for instance-level settings (singleton row).
  """

  alias Forgelet.Repo
  alias Forgelet.Settings.InstanceSetting

  # Fixed UUID for the singleton row — enforced by primary key uniqueness
  @singleton_id "00000000-0000-0000-0000-000000000000"

  @doc """
  Returns the singleton instance settings, creating it if missing.
  """
  def get do
    case Repo.get(InstanceSetting, @singleton_id) do
      nil ->
        %InstanceSetting{id: @singleton_id}
        |> Ecto.Changeset.change(%{})
        |> Repo.insert(on_conflict: :nothing)

        Repo.get!(InstanceSetting, @singleton_id)

      setting ->
        setting
    end
  end

  @doc """
  Updates the instance settings.
  """
  def update(attrs, user_id \\ nil) do
    get()
    |> InstanceSetting.changeset(Map.put(attrs, :updated_by, user_id))
    |> Repo.update()
  end

  @doc """
  Marks onboarding as complete on the instance settings.
  """
  def complete_onboarding(user_id) do
    update(%{onboarding_completed_at: DateTime.utc_now()}, user_id)
  end

  @doc """
  Returns the master plan personality text, or nil.
  """
  def get_personality do
    case Repo.one(InstanceSetting) do
      nil -> nil
      %{master_plan_personality: p} -> p
    end
  end

  @doc """
  Returns true if onboarding has been completed at the instance level.
  """
  def onboarding_completed? do
    case Repo.one(InstanceSetting) do
      nil -> false
      %{onboarding_completed_at: nil} -> false
      _ -> true
    end
  end
end

defmodule WorkersUnite.Settings do
  @moduledoc """
  Context for instance-level settings (singleton row).
  """

  alias WorkersUnite.Repo
  alias WorkersUnite.Settings.InstanceSetting

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

  @doc """
  Returns the default agent model key, or nil if not set.
  """
  def get_default_agent_model do
    case Repo.one(InstanceSetting) do
      nil -> nil
      %{default_agent_model: nil} -> nil
      %{default_agent_model: model} -> model
    end
  end

  @doc """
  Sets the default agent model.
  Validates that the model key exists in the catalog.
  """
  def set_default_agent_model(model_key, user_id \\ nil) do
    if model_key == nil or model_key in valid_model_keys() do
      update(%{default_agent_model: model_key}, user_id)
    else
      {:error, :invalid_model_key}
    end
  end

  defp valid_model_keys do
    model_catalog()
    |> Enum.map(& &1.key)
  end

  @doc """
  Returns the model catalog from config.
  """
  def model_catalog do
    Application.get_env(:workers_unite, :opencode_model_catalog, [])
  end

  @doc """
  Returns the model catalog entry for a given key, or nil.
  """
  def get_model_entry(model_key) do
    Enum.find(model_catalog(), fn entry -> entry.key == model_key end)
  end

  @doc """
  Returns whether a provider has its required credentials configured.
  """
  def provider_configured?(provider) do
    WorkersUnite.CredentialStore.provider_configured?(provider)
  end
end

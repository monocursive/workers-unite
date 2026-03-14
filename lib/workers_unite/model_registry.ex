defmodule WorkersUnite.ModelRegistry do
  @moduledoc """
  Resolves logical model profiles and runtime metadata.

  All agent kinds use the global default model from instance settings,
  which is resolved through the OpenCode model catalog.
  """

  alias WorkersUnite.Settings

  def runtime_config(runtime_name) do
    runtime_registry()
    |> Map.get(runtime_name, %{})
    |> Map.delete(:credentials)
  end

  def runtime_adapter(runtime_name) do
    runtime_config(runtime_name)
    |> Map.get(:adapter)
  end

  def runtime_tools(runtime_name, kind) do
    runtime_config(runtime_name)
    |> Map.get(:native_tools, %{})
    |> Map.get(kind, [])
  end

  def resolve_agent_profile(kind) do
    runtime_name = :opencode
    {model_id, provider} = resolve_model_from_catalog()

    %{
      runtime: runtime_name,
      adapter: runtime_adapter(runtime_name),
      model_class: :default,
      model_id: model_id,
      provider: provider,
      tools: runtime_tools(runtime_name, kind),
      metadata: %{}
    }
  end

  def resolve_model_from_catalog do
    model_key = Settings.get_default_agent_model() || default_model_key()
    catalog = Application.get_env(:workers_unite, :opencode_model_catalog, [])

    case Enum.find(catalog, fn entry -> entry.key == model_key end) do
      nil ->
        raise "Model #{model_key} not found in opencode_model_catalog"

      entry ->
        {entry.model_id, entry.provider}
    end
  end

  defp default_model_key do
    catalog = Application.get_env(:workers_unite, :opencode_model_catalog, [])

    case List.first(catalog) do
      nil -> raise "opencode_model_catalog is empty"
      entry -> entry.key
    end
  end

  defp runtime_registry do
    Application.get_env(:workers_unite, :runtime_registry, %{})
  end
end

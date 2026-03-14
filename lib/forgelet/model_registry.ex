defmodule Forgelet.ModelRegistry do
  @moduledoc """
  Resolves logical model profiles and runtime metadata.

  Agents and workflows should depend on logical model classes rather than raw
  provider model strings.
  """

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
    profile =
      Application.get_env(:forgelet, :agent_profiles, %{})
      |> Map.get(kind)

    runtime_name = Map.fetch!(profile, :runtime)
    model_class = Map.fetch!(profile, :model)

    model =
      runtime_config(runtime_name)
      |> Map.get(:models, %{})
      |> Map.fetch!(model_class)

    %{
      runtime: runtime_name,
      adapter: runtime_adapter(runtime_name),
      model_class: model_class,
      model_id: Map.fetch!(model, :id),
      tools: runtime_tools(runtime_name, kind),
      metadata: Map.drop(model, [:id])
    }
  end

  defp runtime_registry do
    Application.get_env(:forgelet, :runtime_registry, %{})
  end
end

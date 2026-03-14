defmodule WorkersUnite.Agent.RuntimePolicy do
  @moduledoc """
  Chooses a runtime and logical model profile for an agent kind.
  """

  alias WorkersUnite.ModelRegistry

  def profile_for(kind) do
    ModelRegistry.resolve_agent_profile(kind)
  end

  def runtime_module_for(kind) do
    kind
    |> profile_for()
    |> Map.fetch!(:adapter)
  end
end

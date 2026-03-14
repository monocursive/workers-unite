defmodule WorkersUnite.Agent.Session do
  @moduledoc """
  Compatibility wrapper around the configured agent runtime.
  """

  def start_for_agent(owner_pid, agent_id, kind, opts \\ []) do
    runtime_for(kind).start_run(owner_pid, agent_id, kind, opts)
  end

  defp runtime_for(kind) do
    WorkersUnite.Agent.RuntimePolicy.runtime_module_for(kind)
  end
end

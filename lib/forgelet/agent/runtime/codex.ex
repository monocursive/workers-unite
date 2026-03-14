defmodule Forgelet.Agent.Runtime.Codex do
  @moduledoc """
  Placeholder for an API-driven Codex runtime adapter.
  """

  @behaviour Forgelet.Agent.Runtime

  @impl true
  def start_run(_owner_pid, _agent_id, _kind, _opts), do: {:error, :not_implemented}

  @impl true
  def cancel_run(_pid), do: {:error, :not_implemented}

  @impl true
  def capabilities do
    %{mode: :api, tools: [:mcp, :background_jobs]}
  end
end

defmodule Forgelet.Agent.Runtime.Local do
  @moduledoc """
  Deterministic local runtime for tests and simulations.
  """

  use GenServer

  @behaviour Forgelet.Agent.Runtime

  @impl true
  def start_run(owner_pid, _agent_id, _kind, opts) do
    token = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

    case GenServer.start_link(__MODULE__, {owner_pid, opts}) do
      {:ok, pid} -> {:ok, pid, token}
      {:error, _} = error -> error
    end
  end

  @impl true
  def cancel_run(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  @impl true
  def capabilities do
    %{mode: :local, tools: [:deterministic]}
  end

  @impl true
  def init({owner_pid, opts}) do
    send(self(), {:complete, owner_pid, Keyword.get(opts, :output, "local runtime completed")})
    {:ok, %{owner_pid: owner_pid}}
  end

  @impl true
  def handle_info({:complete, owner_pid, output}, state) do
    send(owner_pid, {:session_ended, self(), :completed, output})
    {:stop, :normal, state}
  end
end

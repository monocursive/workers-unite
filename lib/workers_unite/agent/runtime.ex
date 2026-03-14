defmodule WorkersUnite.Agent.Runtime do
  @moduledoc """
  Behavior for model-backed execution runtimes.

  Control-plane orchestration should depend on this contract instead of a
  vendor-specific session implementation.
  """

  @callback start_run(pid(), binary(), atom(), keyword()) ::
              {:ok, pid(), binary()} | {:error, term()}
  @callback cancel_run(pid()) :: :ok | {:error, term()}
  @callback capabilities() :: map()
end

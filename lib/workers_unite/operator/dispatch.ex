defmodule WorkersUnite.Operator.Dispatch do
  @moduledoc """
  Worker selection service for operator-initiated tasks.
  Prefers reusing idle workers over spawning new ones.
  """

  alias WorkersUnite.{Agent, Identity}

  @valid_kinds ~w(coder reviewer orchestrator)a
  @max_agents Application.compile_env(:workers_unite, :max_agents, 50)

  @doc """
  Finds a suitable idle agent of the given kind, or spawns a new one.
  Returns `{:ok, agent_id}` or `{:error, reason}`.
  """
  def find_or_spawn(kind, opts \\ []) do
    case find_idle(kind) do
      {:ok, agent_id} -> {:ok, agent_id}
      :none -> spawn_worker(kind, opts)
      {:error, _} = error -> error
    end
  end

  @doc """
  Finds an idle agent of the given kind.
  Returns `{:ok, agent_id}` or `:none`.
  """
  def find_idle(kind) do
    with {:ok, kind_atom} <- normalize_kind(kind) do
      result =
        Agent.list_local()
        |> Enum.find_value(:none, fn {agent_id, _pid} ->
          try do
            state = Agent.inspect_state(agent_id)

            if state.kind == kind_atom and state.status == :idle do
              {:ok, agent_id}
            else
              nil
            end
          catch
            :exit, _reason -> nil
          end
        end)

      result
    end
  end

  @doc """
  Spawns a new agent of the given kind.
  Returns `{:ok, agent_id}` or `{:error, reason}`.
  """
  def spawn_worker(kind, opts \\ []) do
    with {:ok, kind_atom} <- normalize_kind(kind),
         :ok <- check_agent_limit() do
      # Set the Vault as spawner so provenance links back to the node
      vault_public = Identity.Vault.public_key()
      opts = Keyword.put_new(opts, :spawner, vault_public)

      case Agent.spawn(kind_atom, opts) do
        {:ok, _pid, public_key} -> {:ok, public_key}
        {:error, _} = error -> error
      end
    end
  end

  defp check_agent_limit do
    if length(Agent.list_local()) >= @max_agents do
      {:error, :agent_limit_reached}
    else
      :ok
    end
  end

  @kind_map %{"coder" => :coder, "reviewer" => :reviewer, "orchestrator" => :orchestrator}

  defp normalize_kind(kind) when kind in @valid_kinds, do: {:ok, kind}

  defp normalize_kind(kind) when is_binary(kind) do
    case Map.get(@kind_map, kind) do
      nil -> {:error, :invalid_kind}
      atom -> {:ok, atom}
    end
  end

  defp normalize_kind(_), do: {:error, :invalid_kind}
end

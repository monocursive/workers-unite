defmodule Forgelet.Agent.SessionRegistry do
  @moduledoc """
  Local session token registry for MCP-authenticated Claude sessions.
  """

  use GenServer

  @table :forgelet_sessions

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def create(agent_id, kind, working_dir, owner_user_id \\ nil) do
    GenServer.call(__MODULE__, {:create, agent_id, kind, working_dir, owner_user_id})
  end

  def lookup(token) do
    case :ets.lookup(@table, token) do
      [{^token, data}] -> {:ok, data}
      [] -> :error
    end
  end

  def invalidate(token) do
    GenServer.call(__MODULE__, {:invalidate, token})
  end

  def list_active do
    :ets.tab2list(@table)
    |> Enum.map(fn {token, data} -> Map.put(data, :token, token) end)
  end

  def list_for_user(user_id) do
    list_active()
    |> Enum.filter(fn session -> session[:owner_user_id] == user_id end)
  end

  @impl true
  def init(_state) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create, agent_id, kind, working_dir, owner_user_id}, _from, state) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    session = %{
      agent_id: agent_id,
      kind: kind,
      working_dir: working_dir,
      owner_user_id: owner_user_id,
      created_at: System.system_time(:millisecond)
    }

    true = :ets.insert(@table, {token, session})
    {:reply, {:ok, token}, state}
  end

  def handle_call({:invalidate, token}, _from, state) do
    :ets.delete(@table, token)
    {:reply, :ok, state}
  end
end

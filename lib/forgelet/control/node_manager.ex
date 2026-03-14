defmodule Forgelet.Control.NodeManager do
  @moduledoc """
  Tracks node liveness and capacity for the scheduler.
  """

  use GenServer

  alias Forgelet.Control.Node
  alias Forgelet.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def register_node(attrs) do
    GenServer.call(__MODULE__, {:register_node, attrs})
  end

  def heartbeat(node_id, attrs \\ %{}) do
    GenServer.call(__MODULE__, {:heartbeat, node_id, attrs})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:register_node, attrs}, _from, state) do
    result =
      %Node{}
      |> Node.changeset(Map.put(attrs, :last_heartbeat_at, DateTime.utc_now()))
      |> Repo.insert()

    {:reply, result, state}
  end

  def handle_call({:heartbeat, node_id, attrs}, _from, state) do
    node = Repo.get!(Node, node_id)

    result =
      node
      |> Node.changeset(Map.put(attrs, :last_heartbeat_at, DateTime.utc_now()))
      |> Repo.update()

    {:reply, result, state}
  end
end

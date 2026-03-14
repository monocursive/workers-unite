defmodule WorkersUnite.Control.WorkflowEngine do
  @moduledoc """
  Tracks workflows that are currently active in memory while durable state
  remains in Postgres.
  """

  use GenServer

  alias WorkersUnite.Control.Workflow
  alias WorkersUnite.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{workflows: MapSet.new()},
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  def track(%Workflow{} = workflow) do
    GenServer.call(__MODULE__, {:track, workflow})
  end

  def mark_step(workflow_id, step_name) do
    GenServer.call(__MODULE__, {:mark_step, workflow_id, step_name})
  end

  def active_workflows do
    GenServer.call(__MODULE__, :active_workflows)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:track, %Workflow{} = workflow}, _from, state) do
    Repo.update!(Workflow.changeset(workflow, %{status: "running"}))
    next_state = %{state | workflows: MapSet.put(state.workflows, workflow.id)}
    {:reply, :ok, next_state}
  end

  def handle_call({:mark_step, workflow_id, step_name}, _from, state) do
    workflow = Repo.get!(Workflow, workflow_id)
    Repo.update!(Workflow.changeset(workflow, %{current_step: step_name}))
    {:reply, :ok, state}
  end

  def handle_call(:active_workflows, _from, state) do
    {:reply, MapSet.to_list(state.workflows), state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end

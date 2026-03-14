defmodule WorkersUnite.Control.Master do
  @moduledoc """
  High-level entry point for the control plane.

  The master coordinates durable workflows and jobs but is not itself the
  source of truth. Durable state lives in Postgres and the event log.
  """

  use GenServer

  alias WorkersUnite.Control.{Job, JobScheduler, Reporter, Workflow, WorkflowEngine}
  alias WorkersUnite.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def submit_job(attrs) do
    GenServer.call(__MODULE__, {:submit_job, attrs})
  end

  def start_workflow(attrs) do
    GenServer.call(__MODULE__, {:start_workflow, attrs})
  end

  def system_report do
    Reporter.system_report()
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:submit_job, attrs}, _from, state) do
    result =
      %Job{}
      |> Job.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, job} ->
        :ok = JobScheduler.enqueue(job)
        {:reply, {:ok, Repo.get!(Job, job.id)}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:start_workflow, attrs}, _from, state) do
    result =
      %Workflow{}
      |> Workflow.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, workflow} ->
        :ok = WorkflowEngine.track(workflow)
        {:reply, {:ok, Repo.get!(Workflow, workflow.id)}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end

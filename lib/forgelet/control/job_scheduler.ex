defmodule Forgelet.Control.JobScheduler do
  @moduledoc """
  In-memory queue index for durable jobs stored in Postgres.

  The queue is intentionally reconstructible from the `control_jobs` table.
  """

  use GenServer

  alias Forgelet.Control.Job
  alias Forgelet.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{queued_jobs: MapSet.new()},
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  def enqueue(%Job{} = job) do
    GenServer.call(__MODULE__, {:enqueue, job})
  end

  def queued_jobs do
    GenServer.call(__MODULE__, :queued_jobs)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:enqueue, %Job{} = job}, _from, state) do
    Repo.update!(Job.changeset(job, %{status: "queued", scheduled_at: DateTime.utc_now()}))

    next_state = %{state | queued_jobs: MapSet.put(state.queued_jobs, job.id)}
    {:reply, :ok, next_state}
  end

  def handle_call(:queued_jobs, _from, state) do
    {:reply, MapSet.to_list(state.queued_jobs), state}
  end
end

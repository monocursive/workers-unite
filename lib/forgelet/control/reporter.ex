defmodule Forgelet.Control.Reporter do
  @moduledoc """
  Aggregates control-plane metrics for dashboards and human operators.
  """

  use GenServer

  import Ecto.Query

  alias Forgelet.Control.{Job, Node, Workflow}
  alias Forgelet.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def system_report do
    GenServer.call(__MODULE__, :system_report)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:system_report, _from, state) do
    report = %{
      jobs: summarize(Job),
      workflows: summarize(Workflow),
      nodes: summarize(Node)
    }

    {:reply, report, state}
  end

  defp summarize(schema) do
    Repo.all(from record in schema, select: record.status)
    |> Enum.frequencies()
  end
end

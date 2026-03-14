defmodule WorkersUnite.Control.Node do
  @moduledoc """
  Durable record of a worker or control node participating in the cluster.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @roles ~w(control worker deploy)a
  @statuses ~w(healthy degraded draining down repairing)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "control_nodes" do
    field :name, :string
    field :role, :string
    field :status, :string, default: "healthy"
    field :capacity, :integer, default: 1
    field :active_jobs, :integer, default: 0
    field :runtime_capabilities, {:array, :string}, default: []
    field :version, :string
    field :metadata, :map, default: %{}
    field :last_heartbeat_at, :utc_datetime_usec
    field :drained_at, :utc_datetime_usec

    has_many :job_runs, WorkersUnite.Control.JobRun, foreign_key: :worker_id
    has_many :job_leases, WorkersUnite.Control.JobLease, foreign_key: :worker_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :name,
      :role,
      :status,
      :capacity,
      :active_jobs,
      :runtime_capabilities,
      :version,
      :metadata,
      :last_heartbeat_at,
      :drained_at
    ])
    |> validate_required([:name, :role, :status, :capacity, :active_jobs])
    |> validate_inclusion(:role, Enum.map(@roles, &Atom.to_string/1))
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:active_jobs, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
  end
end

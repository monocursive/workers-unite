defmodule WorkersUnite.Control.JobLease do
  @moduledoc """
  Time-bounded assignment of a job to a worker node.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(active expired released)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "control_job_leases" do
    field :status, :string, default: "active"
    field :lease_expires_at, :utc_datetime_usec
    field :heartbeat_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :job, WorkersUnite.Control.Job
    belongs_to :worker, WorkersUnite.Control.Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(lease, attrs) do
    lease
    |> cast(attrs, [:job_id, :worker_id, :status, :lease_expires_at, :heartbeat_at, :metadata])
    |> validate_required([:job_id, :worker_id, :status, :lease_expires_at])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
  end
end

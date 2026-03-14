defmodule Forgelet.Control.Job do
  @moduledoc """
  Durable unit of scheduled work for the control plane.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending queued assigned running completed failed cancelled)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "control_jobs" do
    field :kind, :string
    field :status, :string, default: "pending"
    field :priority, :integer, default: 100
    field :repo_id, :binary
    field :requested_by, :binary
    field :required_capabilities, {:array, :string}, default: []
    field :runtime_preferences, :map, default: %{}
    field :payload, :map, default: %{}
    field :attempt_count, :integer, default: 0
    field :max_attempts, :integer, default: 3
    field :scheduled_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :workflow, Forgelet.Control.Workflow
    has_many :runs, Forgelet.Control.JobRun
    has_one :lease, Forgelet.Control.JobLease

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :kind,
      :status,
      :priority,
      :workflow_id,
      :repo_id,
      :requested_by,
      :required_capabilities,
      :runtime_preferences,
      :payload,
      :attempt_count,
      :max_attempts,
      :scheduled_at,
      :completed_at
    ])
    |> validate_required([:kind, :status, :priority, :payload, :max_attempts])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_number(:max_attempts, greater_than: 0)
  end
end

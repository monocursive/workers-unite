defmodule Forgelet.Control.JobRun do
  @moduledoc """
  One execution attempt for a control-plane job.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending running completed failed cancelled timed_out)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "control_job_runs" do
    field :runtime, :string
    field :model, :string
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :exit_reason, :string
    field :token_usage, :map, default: %{}
    field :cost_metadata, :map, default: %{}
    field :output_summary, :string
    field :runtime_ref, :string
    field :metadata, :map, default: %{}

    belongs_to :job, Forgelet.Control.Job
    belongs_to :worker, Forgelet.Control.Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :job_id,
      :worker_id,
      :runtime,
      :model,
      :status,
      :started_at,
      :finished_at,
      :exit_reason,
      :token_usage,
      :cost_metadata,
      :output_summary,
      :runtime_ref,
      :metadata
    ])
    |> validate_required([:job_id, :runtime, :status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
  end
end

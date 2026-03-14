defmodule Forgelet.Control.Workflow do
  @moduledoc """
  Durable, resumable orchestration record for a multi-step process.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending running paused completed failed cancelled)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "control_workflows" do
    field :kind, :string
    field :status, :string, default: "pending"
    field :subject_type, :string
    field :subject_id, :binary
    field :current_step, :string
    field :context, :map, default: %{}
    field :started_by, :binary
    field :completed_at, :utc_datetime_usec

    has_many :steps, Forgelet.Control.WorkflowStep
    has_many :jobs, Forgelet.Control.Job

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [
      :kind,
      :status,
      :subject_type,
      :subject_id,
      :current_step,
      :context,
      :started_by,
      :completed_at
    ])
    |> validate_required([:kind, :status, :subject_type])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
  end
end

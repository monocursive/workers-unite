defmodule Forgelet.Control.WorkflowStep do
  @moduledoc """
  Individual step within a workflow.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending running completed failed skipped blocked)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "control_workflow_steps" do
    field :name, :string
    field :status, :string, default: "pending"
    field :depends_on, {:array, :string}, default: []
    field :position, :integer, default: 0
    field :result, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :workflow, Forgelet.Control.Workflow
    belongs_to :job, Forgelet.Control.Job

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :workflow_id,
      :name,
      :status,
      :depends_on,
      :job_id,
      :position,
      :result,
      :started_at,
      :completed_at
    ])
    |> validate_required([:workflow_id, :name, :status, :position])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end

defmodule Forgelet.Repo.Migrations.AddControlPlaneFoundations do
  use Ecto.Migration

  def change do
    create table(:control_workflows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :subject_type, :string, null: false
      add :subject_id, :binary
      add :current_step, :string
      add :context, :map, null: false, default: %{}
      add :started_by, :binary
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:control_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :priority, :integer, null: false, default: 100
      add :workflow_id, references(:control_workflows, type: :binary_id, on_delete: :nilify_all)
      add :repo_id, :binary
      add :requested_by, :binary
      add :required_capabilities, {:array, :string}, null: false, default: []
      add :runtime_preferences, :map, null: false, default: %{}
      add :payload, :map, null: false, default: %{}
      add :attempt_count, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 3
      add :scheduled_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:control_nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :role, :string, null: false
      add :status, :string, null: false, default: "healthy"
      add :capacity, :integer, null: false, default: 1
      add :active_jobs, :integer, null: false, default: 0
      add :runtime_capabilities, {:array, :string}, null: false, default: []
      add :version, :string
      add :metadata, :map, null: false, default: %{}
      add :last_heartbeat_at, :utc_datetime_usec
      add :drained_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:release_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :git_sha, :string, null: false
      add :version, :string, null: false
      add :artifact_uri, :string
      add :compatibility, :map, null: false, default: %{}
      add :rollback_target, :string
      add :status, :string, null: false, default: "draft"
      add :metadata, :map, null: false, default: %{}
      add :released_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :kind, :string, null: false
      add :path_or_uri, :string, null: false
      add :checksum, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:control_job_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :job_id, references(:control_jobs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :worker_id, references(:control_nodes, type: :binary_id, on_delete: :nilify_all)
      add :runtime, :string, null: false
      add :model, :string
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :exit_reason, :string
      add :token_usage, :map, null: false, default: %{}
      add :cost_metadata, :map, null: false, default: %{}
      add :output_summary, :string
      add :runtime_ref, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:control_job_leases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :job_id, references(:control_jobs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :worker_id, references(:control_nodes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "active"
      add :lease_expires_at, :utc_datetime_usec, null: false
      add :heartbeat_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create table(:control_workflow_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workflow_id, references(:control_workflows, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :depends_on, {:array, :string}, null: false, default: []
      add :job_id, references(:control_jobs, type: :binary_id, on_delete: :nilify_all)
      add :position, :integer, null: false, default: 0
      add :result, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:control_jobs, [:status])
    create index(:control_jobs, [:workflow_id])
    create index(:control_jobs, [:kind, :status])
    create index(:control_job_runs, [:job_id])
    create index(:control_job_runs, [:worker_id])
    create index(:control_job_runs, [:status])
    create unique_index(:control_job_leases, [:job_id])
    create index(:control_job_leases, [:worker_id])
    create unique_index(:control_nodes, [:name])
    create index(:control_nodes, [:role, :status])
    create index(:control_workflows, [:kind, :status])
    create unique_index(:control_workflow_steps, [:workflow_id, :name])
    create index(:artifacts, [:owner_type, :owner_id])
    create unique_index(:release_records, [:version])
  end
end

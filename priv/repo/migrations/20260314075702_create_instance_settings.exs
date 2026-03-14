defmodule Forgelet.Repo.Migrations.CreateInstanceSettings do
  use Ecto.Migration

  def change do
    create table(:instance_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :master_plan_personality, :text
      add :onboarding_completed_at, :utc_datetime_usec
      add :created_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :updated_by, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end
  end
end

defmodule WorkersUnite.Repo.Migrations.AddRoleAndOnboardingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "admin"
      add :onboarding_completed_at, :utc_datetime_usec
    end
  end
end

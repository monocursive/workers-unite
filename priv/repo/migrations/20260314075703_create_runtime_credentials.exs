defmodule WorkersUnite.Repo.Migrations.CreateRuntimeCredentials do
  use Ecto.Migration

  def change do
    create table(:runtime_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :key_name, :string, null: false
      add :encrypted_value, :binary, null: false
      add :created_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :updated_by, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:runtime_credentials, [:provider, :key_name])
  end
end

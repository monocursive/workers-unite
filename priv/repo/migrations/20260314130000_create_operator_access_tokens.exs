defmodule WorkersUnite.Repo.Migrations.CreateOperatorAccessTokens do
  use Ecto.Migration

  def change do
    create table(:operator_access_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_prefix, :string
      add :token_hash, :binary, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:operator_access_tokens, [:token_hash])
    create index(:operator_access_tokens, [:user_id])
  end
end

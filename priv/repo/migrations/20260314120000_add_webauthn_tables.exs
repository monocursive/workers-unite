defmodule WorkersUnite.Repo.Migrations.AddWebauthnTables do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :integer, null: false, default: 0
      add :transports, {:array, :string}, default: []
      add :friendly_name, :string
      add :last_used_at, :utc_datetime
      add :aaguid, :binary

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webauthn_credentials, [:credential_id])
    create index(:webauthn_credentials, [:user_id])

    create table(:webauthn_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token_hash, :binary, null: false
      add :purpose, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :challenge_data, :binary, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webauthn_challenges, [:token_hash])
    create index(:webauthn_challenges, [:expires_at])

    # Delete all existing "login" context tokens (magic-link tokens)
    execute "DELETE FROM users_tokens WHERE context = 'login'", ""
  end
end

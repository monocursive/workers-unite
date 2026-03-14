defmodule WorkersUnite.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary, primary_key: true
      add :kind, :string, null: false
      add :author, :binary, null: false
      add :payload, :map, default: %{}
      add :timestamp, :bigint, null: false
      add :signature, :binary, null: false
      add :references, {:array, :map}, default: []
      add :scope_type, :string
      add :scope_id, :binary
    end

    create index(:events, [:kind])
    create index(:events, [:author])
    create index(:events, [:scope_type, :scope_id])
    create index(:events, [:timestamp])
  end
end

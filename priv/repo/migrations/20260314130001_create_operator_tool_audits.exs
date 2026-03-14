defmodule WorkersUnite.Repo.Migrations.CreateOperatorToolAudits do
  use Ecto.Migration

  def change do
    create table(:operator_tool_audits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :token_id, references(:operator_access_tokens, type: :binary_id, on_delete: :nilify_all)
      add :tool_name, :string, null: false
      add :arguments_summary, :map
      add :result_status, :string, null: false
      add :result_ref, :string
      add :client_name, :string

      timestamps(type: :utc_datetime)
    end

    create index(:operator_tool_audits, [:user_id])
  end
end

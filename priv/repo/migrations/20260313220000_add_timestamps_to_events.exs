defmodule WorkersUnite.Repo.Migrations.AddTimestampsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      timestamps(type: :utc_datetime_usec, default: fragment("NOW()"))
    end
  end
end

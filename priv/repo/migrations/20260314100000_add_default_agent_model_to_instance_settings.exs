defmodule WorkersUnite.Repo.Migrations.AddDefaultAgentModelToInstanceSettings do
  use Ecto.Migration

  def change do
    alter table(:instance_settings) do
      add :default_agent_model, :string
    end
  end
end

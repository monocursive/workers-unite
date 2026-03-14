defmodule WorkersUnite.Settings.InstanceSetting do
  @moduledoc """
  Singleton Ecto schema for instance-wide settings such as master-plan personality and onboarding state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "instance_settings" do
    field :master_plan_personality, :string
    field :onboarding_completed_at, :utc_datetime_usec
    field :default_agent_model, :string
    belongs_to :created_by_user, WorkersUnite.Accounts.User, foreign_key: :created_by
    belongs_to :updated_by_user, WorkersUnite.Accounts.User, foreign_key: :updated_by

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [
      :master_plan_personality,
      :onboarding_completed_at,
      :default_agent_model,
      :updated_by
    ])
    |> validate_length(:master_plan_personality, max: 10_000)
    |> validate_length(:default_agent_model, max: 255)
  end
end

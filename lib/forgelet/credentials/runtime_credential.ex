defmodule Forgelet.Credentials.RuntimeCredential do
  @moduledoc """
  Ecto schema for provider credentials stored with AES-256-GCM encryption.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runtime_credentials" do
    field :provider, :string
    field :key_name, :string
    field :encrypted_value, :binary
    belongs_to :created_by_user, Forgelet.Accounts.User, foreign_key: :created_by
    belongs_to :updated_by_user, Forgelet.Accounts.User, foreign_key: :updated_by

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:provider, :key_name, :encrypted_value, :created_by, :updated_by])
    |> validate_required([:provider, :key_name, :encrypted_value])
    |> unique_constraint([:provider, :key_name])
  end
end

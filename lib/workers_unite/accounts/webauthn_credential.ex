defmodule WorkersUnite.Accounts.WebauthnCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webauthn_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :transports, {:array, :string}, default: []
    field :friendly_name, :string
    field :last_used_at, :utc_datetime
    field :aaguid, :binary
    belongs_to :user, WorkersUnite.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :credential_id,
      :public_key,
      :sign_count,
      :transports,
      :friendly_name,
      :last_used_at,
      :aaguid,
      :user_id
    ])
    |> validate_required([:credential_id, :public_key, :user_id])
    |> unique_constraint(:credential_id)
  end

  def rename_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:friendly_name])
    |> validate_required([:friendly_name])
    |> validate_length(:friendly_name, max: 100)
  end
end

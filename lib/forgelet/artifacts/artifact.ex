defmodule Forgelet.Artifacts.Artifact do
  @moduledoc """
  Metadata for logs, proof bundles, patches, and release outputs.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "artifacts" do
    field :owner_type, :string
    field :owner_id, :binary_id
    field :kind, :string
    field :path_or_uri, :string
    field :checksum, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:owner_type, :owner_id, :kind, :path_or_uri, :checksum, :metadata])
    |> validate_required([:owner_type, :owner_id, :kind, :path_or_uri])
  end
end

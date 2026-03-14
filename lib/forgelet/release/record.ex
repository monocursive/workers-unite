defmodule Forgelet.Release.Record do
  @moduledoc """
  Immutable release metadata used by deployment workflows.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(draft ready deployed rolled_back failed)a

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "release_records" do
    field :git_sha, :string
    field :version, :string
    field :artifact_uri, :string
    field :compatibility, :map, default: %{}
    field :rollback_target, :string
    field :status, :string, default: "draft"
    field :metadata, :map, default: %{}
    field :released_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :git_sha,
      :version,
      :artifact_uri,
      :compatibility,
      :rollback_target,
      :status,
      :metadata,
      :released_at
    ])
    |> validate_required([:git_sha, :version, :status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> unique_constraint(:version)
  end
end

defmodule Journalex.MetadataDrafts.Draft do
  @moduledoc """
  Schema for named metadata draft templates.

  Each draft stores a name, a metadata_version (1 or 2), and a metadata
  JSONB map matching the corresponding V1/V2 metadata structure. Drafts
  can be applied to trades to quickly populate metadata fields.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "metadata_drafts" do
    field :name, :string
    field :metadata_version, :integer
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(name metadata_version)a
  @optional ~w(metadata)a

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:metadata_version, [1, 2])
    |> unique_constraint([:name, :metadata_version],
      name: :metadata_drafts_name_metadata_version_index,
      message: "a draft with this name already exists for this version"
    )
  end
end

defmodule Journalex.CombinedDrafts.Draft do
  @moduledoc """
  Schema for combined draft templates that pair a metadata draft with a writeup draft.

  Each combined draft has a unique name and optional references to a metadata draft
  and a writeup draft. When applied to a trade, both referenced drafts are applied
  in a single action. Either reference can be nil for partial combos (metadata-only
  or writeup-only).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "combined_drafts" do
    field :name, :string

    belongs_to :metadata_draft, Journalex.MetadataDrafts.Draft
    belongs_to :writeup_draft, Journalex.WriteupDrafts.Draft

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(name)a
  @optional ~w(metadata_draft_id writeup_draft_id)a

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name,
      name: :combined_drafts_name_index,
      message: "a combined draft with this name already exists"
    )
    |> foreign_key_constraint(:metadata_draft_id)
    |> foreign_key_constraint(:writeup_draft_id)
  end
end

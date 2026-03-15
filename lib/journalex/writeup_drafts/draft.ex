defmodule Journalex.WriteupDrafts.Draft do
  @moduledoc """
  Schema for named writeup draft templates.

  Each draft stores a name and a list of block maps representing the page body
  content (toggles, paragraphs) that can be applied to trades and pushed as
  Notion page blocks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "writeup_drafts" do
    field :name, :string
    field :blocks, {:array, :map}, default: []
    field :is_preset, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(name)a
  @optional ~w(blocks is_preset)a

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name,
      name: :writeup_drafts_name_index,
      message: "a writeup draft with this name already exists"
    )
  end
end

defmodule Journalex.WriteupDrafts.PresetBlock do
  @moduledoc """
  Schema for reusable preset block snippets.

  Each preset block stores a name and a list of block maps (same format as
  Draft blocks) that can be inserted into any writeup draft at a chosen position.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "preset_blocks" do
    field :name, :string
    field :blocks, {:array, :map}, default: []
    field :group, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(name)a
  @optional ~w(blocks group)a

  def changeset(preset_block, attrs) do
    preset_block
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:group, max: 100)
    |> unique_constraint(:name,
      name: :preset_blocks_name_index,
      message: "a preset block with this name already exists"
    )
  end
end

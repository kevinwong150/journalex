defmodule Journalex.Repo.Migrations.CreatePresetBlocks do
  use Ecto.Migration

  def change do
    create table(:preset_blocks) do
      add :name, :string, null: false
      add :blocks, :map, default: "[]", null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:preset_blocks, [:name])
  end
end

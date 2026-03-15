defmodule Journalex.Repo.Migrations.CreateWriteupDrafts do
  use Ecto.Migration

  def change do
    create table(:writeup_drafts) do
      add :name, :string, null: false
      add :blocks, :map, default: "[]", null: false
      add :is_preset, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:writeup_drafts, [:name])
  end
end

defmodule Journalex.Repo.Migrations.CreateMetadataDrafts do
  use Ecto.Migration

  def change do
    create table(:metadata_drafts) do
      add :name, :string, null: false
      add :metadata_version, :integer, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:metadata_drafts, [:metadata_version])
    create unique_index(:metadata_drafts, [:name, :metadata_version])
  end
end

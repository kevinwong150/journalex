defmodule Journalex.Repo.Migrations.AddJournalDataToMetadataDrafts do
  use Ecto.Migration

  def change do
    alter table(:metadata_drafts) do
      add :journal_data, :map, default: %{}, null: false
    end
  end
end

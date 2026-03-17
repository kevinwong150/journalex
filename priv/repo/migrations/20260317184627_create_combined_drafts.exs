defmodule Journalex.Repo.Migrations.CreateCombinedDrafts do
  use Ecto.Migration

  def change do
    create table(:combined_drafts) do
      add :name, :string, null: false
      add :metadata_draft_id, references(:metadata_drafts, on_delete: :nilify_all)
      add :writeup_draft_id, references(:writeup_drafts, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:combined_drafts, [:name])
    create index(:combined_drafts, [:metadata_draft_id])
    create index(:combined_drafts, [:writeup_draft_id])
  end
end

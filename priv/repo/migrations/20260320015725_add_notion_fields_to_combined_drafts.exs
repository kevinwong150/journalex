defmodule Journalex.Repo.Migrations.AddNotionFieldsToCombinedDrafts do
  use Ecto.Migration

  def change do
    alter table(:combined_drafts) do
      add :notion_page_id, :string
      add :applied_at, :utc_datetime_usec
    end

    create unique_index(:combined_drafts, [:notion_page_id],
      where: "notion_page_id IS NOT NULL",
      name: :combined_drafts_notion_page_id_index
    )
  end
end

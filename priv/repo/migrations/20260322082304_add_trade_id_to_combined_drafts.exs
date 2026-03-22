defmodule Journalex.Repo.Migrations.AddTradeIdToCombinedDrafts do
  use Ecto.Migration

  def change do
    alter table(:combined_drafts) do
      add :trade_id, references(:trades, on_delete: :nilify_all)
    end

    create unique_index(:combined_drafts, [:trade_id],
      where: "trade_id IS NOT NULL",
      name: :combined_drafts_trade_id_index
    )
  end
end

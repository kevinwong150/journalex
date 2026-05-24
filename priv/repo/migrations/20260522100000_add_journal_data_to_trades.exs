defmodule Journalex.Repo.Migrations.AddJournalDataToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      add :journal_data, :map, default: %{}
    end

    create index(:trades, [:journal_data], using: :gin)
  end
end

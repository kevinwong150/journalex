defmodule Journalex.Repo.Migrations.AddDurationToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      add :duration, :integer, comment: "Duration in seconds from open to close position"
    end

    create index(:trades, [:duration])
  end
end

defmodule Journalex.Repo.Migrations.AddWriteupToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      add :writeup, :map
    end
  end
end

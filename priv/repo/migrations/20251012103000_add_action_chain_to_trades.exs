defmodule Journalex.Repo.Migrations.AddActionChainToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      add :action_chain, :map
    end
  end
end

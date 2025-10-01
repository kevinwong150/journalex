defmodule Journalex.Repo.Migrations.AddUniqueIndexTradesFields do
  use Ecto.Migration

  def change do
    create unique_index(:trades, [:datetime, :ticker, :aggregated_side, :realized_pl],
             name: :trades_unique_dt_ticker_side_pl
           )
  end
end

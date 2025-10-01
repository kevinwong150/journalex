defmodule Journalex.Repo.Migrations.CreateTrades do
  use Ecto.Migration

  def change do
    create table(:trades) do
      add :datetime, :utc_datetime, null: false
      add :ticker, :string, null: false
      add :aggregated_side, :string, null: false
      add :result, :string, null: false
      add :realized_pl, :decimal, precision: 18, scale: 2, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trades, [:datetime])
    create index(:trades, [:ticker])
    create index(:trades, [:aggregated_side])
    create index(:trades, [:result])
    create index(:trades, [:datetime, :ticker])

    # Basic data validation at DB level
    create constraint(:trades, :result_valid, check: "result in ('WIN','LOSE')")
    create constraint(:trades, :aggregated_side_valid, check: "aggregated_side in ('LONG','SHORT','-')")
  end
end

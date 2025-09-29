defmodule Journalex.Repo.Migrations.CreateActivityStatements do
  use Ecto.Migration

  def change do
    create table(:activity_statements) do
      add :datetime, :utc_datetime_usec, null: false
      add :side, :string, null: false
      add :position_action, :string, null: false
      add :symbol, :string, null: false
      add :asset_category, :string, null: false
      add :currency, :string, null: false

      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :trade_price, :decimal, precision: 20, scale: 8, null: false
      add :proceeds, :decimal, precision: 20, scale: 8
      add :comm_fee, :decimal, precision: 20, scale: 8
      add :realized_pl, :decimal, precision: 20, scale: 8

      timestamps(type: :utc_datetime_usec)
    end

    create index(:activity_statements, [:datetime])
    create index(:activity_statements, [:symbol])
    create index(:activity_statements, [:side])
    create index(:activity_statements, [:position_action])

    create constraint(
             :activity_statements,
             :side_must_be_long_or_short,
             check: "side in ('long','short')"
           )

    create constraint(
             :activity_statements,
             :position_action_must_be_build_or_close,
             check: "position_action in ('build','close')"
           )
  end
end

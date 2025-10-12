defmodule Journalex.Trades.Trade do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Trade schema storing aggregated close trades for analysis.
  Fields mirror AggregatedTradeList columns.
  """

  schema "trades" do
    field :datetime, :utc_datetime
    field :ticker, :string
    field :aggregated_side, :string
    field :result, :string
    field :realized_pl, :decimal
    field :action_chain, :map
    field :duration, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(datetime ticker aggregated_side result realized_pl)a
  @optional ~w(action_chain duration)a

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:result, ["WIN", "LOSE"])
    |> validate_inclusion(:aggregated_side, ["LONG", "SHORT", "-"])
  end
end

defmodule Journalex.ActivityStatement do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Ecto schema for activity_statements rows parsed from Activity Statement CSV.
  """

  schema "activity_statements" do
    field :datetime, :utc_datetime_usec
    field :side, :string
    field :symbol, :string
    field :asset_category, :string
    field :currency, :string

    field :quantity, :decimal
    field :trade_price, :decimal
    field :proceeds, :decimal
    field :comm_fee, :decimal
    field :realized_pl, :decimal

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(datetime side symbol asset_category currency quantity trade_price)a
  @optional ~w(proceeds comm_fee realized_pl)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:side, ["buy", "sell"])
  end
end

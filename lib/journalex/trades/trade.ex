defmodule Journalex.Trades.Trade do
  use Ecto.Schema
  import Ecto.Changeset

  alias Journalex.Trades.TradeMetadata

  @moduledoc """
  Trade schema storing aggregated close trades for analysis.
  Fields mirror AggregatedTradeList columns.

  Metadata field stores Notion integration data and analysis flags as JSONB.
  """

  schema "trades" do
    field :datetime, :utc_datetime
    field :ticker, :string
    field :aggregated_side, :string
    field :result, :string
    field :realized_pl, :decimal
    field :action_chain, :map
    field :duration, :integer

    embeds_one :metadata, TradeMetadata, on_replace: :update

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(datetime ticker aggregated_side result realized_pl)a
  @optional ~w(action_chain duration)a

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, @required ++ @optional)
    |> cast_embed(:metadata, with: &TradeMetadata.changeset/2)
    |> validate_required(@required)
    |> validate_inclusion(:result, ["WIN", "LOSE"])
    |> validate_inclusion(:aggregated_side, ["LONG", "SHORT", "-"])
  end

  @doc """
  Partially update metadata fields without replacing the entire metadata structure.

  This allows incremental updates like adding a single flag or updating one field
  while preserving all other metadata values.

  ## Examples

      iex> trade |> Trade.update_metadata(%{done?: true})
      iex> trade |> Trade.update_metadata(%{sector: "Technology", hot_sector?: true})
  """
  def update_metadata(%__MODULE__{} = trade, metadata_changes) when is_map(metadata_changes) do
    current_metadata = trade.metadata || %TradeMetadata{}
    current_map = Map.from_struct(current_metadata)

    # Merge changes into current metadata, keeping unchanged fields
    merged = Map.merge(current_map, metadata_changes)

    changeset(trade, %{metadata: merged})
  end

  @doc """
  Set the Notion page ID for this trade.
  """
  def set_notion_page_id(%__MODULE__{} = trade, page_id) when is_binary(page_id) do
    update_metadata(trade, %{notion_page_id: page_id})
  end

  @doc """
  Mark trade as done (completed/reviewed).
  """
  def mark_done(%__MODULE__{} = trade) do
    update_metadata(trade, %{done?: true})
  end

  @doc """
  Mark trade as not done.
  """
  def mark_not_done(%__MODULE__{} = trade) do
    update_metadata(trade, %{done?: false})
  end

  @doc """
  Add multiple analysis flags at once.

  ## Examples

      iex> trade |> Trade.add_analysis_flags(%{
      ...>   momentum?: true,
      ...>   hot_sector?: true,
      ...>   align_with_trend?: true
      ...> })
  """
  def add_analysis_flags(%__MODULE__{} = trade, flags) when is_map(flags) do
    update_metadata(trade, flags)
  end
end

defmodule Journalex.Trades.Trade do
  use Ecto.Schema
  import Ecto.Changeset
  require Logger

  alias Journalex.Trades.Metadata.V1, as: MetadataV1
  alias Journalex.Trades.Metadata.V2, as: MetadataV2

  @moduledoc """
  Trade schema storing aggregated close trades for analysis.
  Fields mirror AggregatedTradeList columns.

  Metadata field stores Notion integration data and analysis flags as JSONB.
  Supports multiple metadata versions (V1, V2, etc.) based on metadata_version field.
  """

  schema "trades" do
    field :datetime, :utc_datetime
    field :ticker, :string
    field :aggregated_side, :string
    field :result, :string
    field :realized_pl, :decimal
    field :action_chain, :map
    field :duration, :integer
    field :metadata_version, :integer

    # Polymorphic metadata - actual type determined by metadata_version
    field :metadata, :map

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(datetime ticker aggregated_side result realized_pl)a
  @optional ~w(action_chain duration metadata_version metadata)a

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, @required ++ @optional)
    |> cast_polymorphic_metadata(attrs)
    |> validate_required(@required)
    |> validate_inclusion(:result, ["WIN", "LOSE"])
    |> validate_inclusion(:aggregated_side, ["LONG", "SHORT", "-"])
  end

  # Cast metadata based on version
  defp cast_polymorphic_metadata(changeset, attrs) do
    version = get_field(changeset, :metadata_version) || Map.get(attrs, :metadata_version)
    metadata_attrs = Map.get(attrs, :metadata)

    if metadata_attrs do
      case version do
        1 ->
          case MetadataV1.changeset(%MetadataV1{}, metadata_attrs) |> apply_action(:insert) do
            {:ok, metadata_struct} ->
              put_change(changeset, :metadata, Map.from_struct(metadata_struct))
            {:error, meta_changeset} ->
              Logger.warning("V1 metadata validation failed: #{inspect(meta_changeset.errors)}")
              changeset
          end

        2 ->
          case MetadataV2.changeset(%MetadataV2{}, metadata_attrs) |> apply_action(:insert) do
            {:ok, metadata_struct} ->
              put_change(changeset, :metadata, Map.from_struct(metadata_struct))
            {:error, meta_changeset} ->
              Logger.warning("V2 metadata validation failed: #{inspect(meta_changeset.errors)}")
              changeset
          end

        _ ->
          changeset
      end
    else
      changeset
    end
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
    current_metadata = trade.metadata || %{}

    # Merge changes into current metadata
    merged = Map.merge(current_metadata, metadata_changes)

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

  @doc """
  Set the metadata version for this trade.
  """
  def set_metadata_version(%__MODULE__{} = trade, version) when is_integer(version) do
    changeset(trade, %{metadata_version: version})
  end

  @doc """
  Check if trade has any metadata.
  """
  def has_metadata?(%__MODULE__{metadata: nil}), do: false
  def has_metadata?(%__MODULE__{metadata: metadata}) when is_map(metadata) and map_size(metadata) > 0, do: true
  def has_metadata?(_), do: false
end

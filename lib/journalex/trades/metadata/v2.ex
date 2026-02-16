defmodule Journalex.Trades.Metadata.V2 do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  V2 metadata schema for trades - enhanced Notion structure with advanced analysis.

  Structure may evolve over time - old records may have different field sets.
  All fields are optional to support partial data and schema evolution.
  """

  @primary_key false
  embedded_schema do
    # Notion integration
    field :notion_page_id, :string

    # Status & control
    field :done?, :boolean, default: false
    field :lost_data?, :boolean, default: false
    field :trademark, :string

    # Trade classification
    field :rank, :string
    field :setup, :string
    field :close_trigger, :string
    field :sector, :string
    field :cap_size, :string

    # Risk/reward metrics
    field :initial_risk_reward_ratio, :decimal
    field :best_risk_reward_ratio, :decimal

    # Position sizing
    field :size, :decimal
    field :order_type, :string

    # Time analysis
    field :entry_timeslot, :string
    field :close_timeslot, :string

    # Trade characteristics - Boolean flags
    # Note: Some like win? and long_trade? are calculated fields in Notion for view functionality
    # field :win?, :boolean, default: false
    # field :long_trade?, :boolean, default: false
    field :revenge_trade?, :boolean, default: false
    field :fomo?, :boolean, default: false
    field :add_size?, :boolean, default: false
    field :adjusted_risk_reward?, :boolean, default: false
    field :align_with_trend?, :boolean, default: false
    field :better_risk_reward_ratio?, :boolean, default: false
    field :big_picture?, :boolean, default: false
    field :earning_report?, :boolean, default: false
    field :follow_up_trial?, :boolean, default: false
    field :good_lesson?, :boolean, default: false
    field :hot_sector?, :boolean, default: false
    field :momentum?, :boolean, default: false
    field :news?, :boolean, default: false
    field :normal_emotion?, :boolean, default: false
    field :operation_mistake?, :boolean, default: false
    field :overnight?, :boolean, default: false
    field :overnight_in_purpose?, :boolean, default: false
    field :skipped_position?, :boolean, default: false

    # Comments & notes
    field :close_time_comment, :string

    # Link/reference fields
    # field :date_link, :string
    # field :ticker_link, :string
  end

  @rank_values ["Not Setup", "C Trade", "B Trade", "A Trade"]
  # @cap_size_values ["Large", "Mid", "Small"]

  @doc """
  Changeset for TradeMetadata.

  All fields are optional to support partial updates and schema evolution.
  Validates enum values for rank and cap_size when present.
  """
  def changeset(metadata, attrs) do
    metadata
    |> cast(attrs, [
      :notion_page_id,
      :done?,
      :lost_data?,
      :trademark,
      :rank,
      :setup,
      :close_trigger,
      :sector,
      :cap_size,
      :initial_risk_reward_ratio,
      :best_risk_reward_ratio,
      :size,
      :order_type,
      :entry_timeslot,
      :close_timeslot,
      # :win?,
      # :long_trade?,
      :revenge_trade?,
      :fomo?,
      :add_size?,
      :adjusted_risk_reward?,
      :align_with_trend?,
      :better_risk_reward_ratio?,
      :big_picture?,
      :earning_report?,
      :follow_up_trial?,
      :good_lesson?,
      :hot_sector?,
      :momentum?,
      :news?,
      :normal_emotion?,
      :operation_mistake?,
      :overnight?,
      :overnight_in_purpose?,
      :skipped_position?,
      :close_time_comment,
      # :date_link,
      # :ticker_link
    ])
    |> validate_inclusion(:rank, @rank_values)
    # |> validate_inclusion(:cap_size, @cap_size_values)
  end

  @doc """
  Create a new TradeMetadata struct from a map, typically from Notion API response.
  """
  def new(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end
end

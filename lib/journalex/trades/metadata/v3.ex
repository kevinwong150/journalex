defmodule Journalex.Trades.Metadata.V3 do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  V3 metadata schema — clean redesign of V2.

  Key differences from V2:
  - 40 boolean flags (vs ~28 in V2); several renamed, 8 V2 flags dropped, 17 new
  - `size_in_r` (auto-computed: |pl|/r_size) + `r_value` (1R dollar amount) replace `size`
  - 5 multi_select fields: close_time_comment, extra_setup_comment, good_things, patterns, regular_lessons
  - Rank has 5 options ("BAD Trade" removed); Setup has 7 options
  - `sector` and `cap_size` are rollup read-only fields — never written to Notion

  IMPORTANT: This module is NOT a superset of V2. V2 fields like :add_size?, :momentum?, etc.
  do not exist in V3. Never mix V2 field names into a V3 record.
  """

  @primary_key false
  embedded_schema do
    # Notion integration
    field :notion_page_id, :string

    # Trade classification
    field :rank, :string
    field :setup, :string
    field :close_trigger, :string
    field :order_type, :string

    # Rollups — read-only from Notion, never written back
    field :sector, :string
    field :cap_size, :string

    # Risk/reward metrics
    field :initial_risk_reward_ratio, :decimal
    field :best_risk_reward_ratio, :decimal

    # Position sizing (V3 replaces V2's single :size with two fields)
    field :size_in_r, :decimal    # auto-computed: abs(realized_pl) / r_size
    field :r_value, :decimal      # 1R dollar amount from config

    # Time analysis
    field :entry_timeslot, :string
    field :close_timeslot, :string

    # Progress indicators (V3-only)
    field :target_progress, :string    # "25%", "50%", "75%"
    field :stoploss_progress, :string  # "25%", "50%", "75%"

    # Multi-select fields (stored as comma-separated strings)
    field :close_time_comment, :string
    field :extra_setup_comment, :string
    field :good_things, :string
    field :patterns, :string
    field :regular_lessons, :string

    # ─── Boolean flags ──────────────────────────────────────────────────────

    # Status & control
    field :done?, :boolean, default: false
    field :lost_data?, :boolean, default: false

    # Carried over from V2 (19 flags)
    field :better_risk_reward_ratio?, :boolean, default: false
    field :choppy_chart?, :boolean, default: false          # V2 had :choppychart? (typo fixed)
    field :close_trade_remorse?, :boolean, default: false
    field :earning_report?, :boolean, default: false
    field :fomo?, :boolean, default: false
    field :follow_up_trial?, :boolean, default: false
    field :fully_wrong_direction?, :boolean, default: false
    field :good_lesson?, :boolean, default: false
    field :hot_sector?, :boolean, default: false
    field :mid_range?, :boolean, default: false
    field :news?, :boolean, default: false
    field :normal_emotion?, :boolean, default: false
    field :operation_mistake?, :boolean, default: false
    field :overnight?, :boolean, default: false
    field :overnight_in_purpose?, :boolean, default: false
    field :revenge_trade?, :boolean, default: false
    field :too_tight_stop_loss?, :boolean, default: false

    # Renamed from V2 (4 flags — different atom keys)
    field :decision_affected_by_other_trade?, :boolean, default: false  # was :affected_by_other_trade?
    field :slippage_entry?, :boolean, default: false                     # was :slipped_position?
    field :align_ticker_big_picture_trend?, :boolean, default: false     # was :big_picture?
    field :align_ticker_intraday_trend?, :boolean, default: false        # was :align_with_trend?

    # New in V3 (17 flags)
    field :adjusted_stoploss?, :boolean, default: false
    field :adjusted_target?, :boolean, default: false
    field :align_global_trend?, :boolean, default: false
    field :align_sector_trend?, :boolean, default: false
    field :averaging_down?, :boolean, default: false
    field :averaging_up?, :boolean, default: false
    field :following_trade?, :boolean, default: false
    field :lack_confidence?, :boolean, default: false
    field :large_size_in_purpose?, :boolean, default: false
    field :small_size_in_purpose?, :boolean, default: false
    field :reasonable_entry_story?, :boolean, default: false
    field :reasonable_exit_story?, :boolean, default: false
    field :scalp?, :boolean, default: false
    field :should_record_obsidian?, :boolean, default: false
    field :size_matching_story?, :boolean, default: false
    field :too_loose_stop_loss?, :boolean, default: false
    field :use_draft_order?, :boolean, default: false
    field :random_intraday_trend?, :boolean, default: false
  end

  @rank_values ["Not Setup", "Bad Setup", "C Trade", "B Trade", "A Trade"]

  @setup_values [
    "Bouncy Ball - Big Seller/Buyer",
    "Breakout - Day High/Low",
    "Reversal - Capitulation",
    "Reversal - Day High/Low",
    "Reversal - Pullback Reversal",
    "Testing Setup",
    "Not Setup"
  ]

  @close_trigger_values [
    "Automatically - Breakeven",
    "Automatically - Take Profit",
    "Automatically - Stop Loss",
    "Manually - Take Profit",
    "Manually - Stop Loss",
    "Manually - Reverse"
  ]

  @order_type_values ["Limit Order", "Stop Order", "Market Order"]

  @progress_values ["25%", "50%", "75%"]

  @boolean_fields ~w(
    done? lost_data?
    better_risk_reward_ratio? choppy_chart? close_trade_remorse? earning_report?
    fomo? follow_up_trial? fully_wrong_direction? good_lesson? hot_sector? mid_range?
    news? normal_emotion? operation_mistake? overnight? overnight_in_purpose?
    revenge_trade? too_tight_stop_loss?
    decision_affected_by_other_trade? slippage_entry?
    align_ticker_big_picture_trend? align_ticker_intraday_trend?
    adjusted_stoploss? adjusted_target? align_global_trend? align_sector_trend?
    averaging_down? averaging_up? following_trade? lack_confidence?
    large_size_in_purpose? small_size_in_purpose?
    reasonable_entry_story? reasonable_exit_story?
    scalp? should_record_obsidian? size_matching_story?
    too_loose_stop_loss? use_draft_order?
    random_intraday_trend?
  )a

  @doc """
  Changeset for V3 metadata.

  All fields are optional to support partial updates and schema evolution.
  Validates enum values when present.
  """
  def changeset(metadata, attrs) do
    metadata
    |> cast(attrs, [
      :notion_page_id,
      :rank,
      :setup,
      :close_trigger,
      :order_type,
      :sector,
      :cap_size,
      :initial_risk_reward_ratio,
      :best_risk_reward_ratio,
      :size_in_r,
      :r_value,
      :entry_timeslot,
      :close_timeslot,
      :target_progress,
      :stoploss_progress,
      :close_time_comment,
      :extra_setup_comment,
      :good_things,
      :patterns,
      :regular_lessons
      | @boolean_fields
    ])
    |> validate_inclusion(:rank, @rank_values, message: "must be one of: #{Enum.join(@rank_values, ", ")}")
    |> validate_inclusion(:setup, @setup_values, message: "must be one of: #{Enum.join(@setup_values, ", ")}")
    |> validate_inclusion(:close_trigger, @close_trigger_values)
    |> validate_inclusion(:order_type, @order_type_values)
    |> validate_inclusion(:target_progress, @progress_values)
    |> validate_inclusion(:stoploss_progress, @progress_values)
  end

  @doc """
  Create a new V3 metadata struct from a map.
  """
  def new(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end
end

defmodule JournalexWeb.MetadataParamsBuilder do
  @moduledoc """
  Converts HTML form params (string-keyed maps) into atom-keyed metadata maps
  suitable for metadata draft storage.

  Used by MetadataDraftLive and TradeDraftLive to avoid duplicating the
  form-params-to-metadata conversion logic.
  """

  @doc """
  Build a metadata map from form params for the given version (1 or 2).
  Returns an empty map for unsupported versions.
  """
  def build(params, version) do
    case version do
      1 -> build_v1(params)
      2 -> build_v2(params)
      3 -> build_v3(params)
      _ -> %{}
    end
  end

  defp build_v1(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      operation_mistake?: params["operation_mistake"] == "true",
      follow_setup?: params["follow_setup"] == "true",
      follow_stop_loss_management?: params["follow_stop_loss_management"] == "true",
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      unnecessary_trade?: params["unnecessary_trade"] == "true",
      close_time_comment: join_close_time_comments(params["close_time_comment"])
    }
  end

  defp build_v2(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      order_type: parse_string(params["order_type"]),
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      add_size?: params["add_size"] == "true",
      adjusted_risk_reward?: params["adjusted_risk_reward"] == "true",
      align_with_trend?: params["align_with_trend"] == "true",
      better_risk_reward_ratio?: params["better_risk_reward_ratio"] == "true",
      big_picture?: params["big_picture"] == "true",
      earning_report?: params["earning_report"] == "true",
      follow_up_trial?: params["follow_up_trial"] == "true",
      good_lesson?: params["good_lesson"] == "true",
      hot_sector?: params["hot_sector"] == "true",
      momentum?: params["momentum"] == "true",
      news?: params["news"] == "true",
      normal_emotion?: params["normal_emotion"] == "true",
      operation_mistake?: params["operation_mistake"] == "true",
      overnight?: params["overnight"] == "true",
      overnight_in_purpose?: params["overnight_in_purpose"] == "true",
      slipped_position?: params["slipped_position"] == "true",
      choppychart?: params["choppychart"] == "true",
      close_trade_remorse?: params["close_trade_remorse"] == "true",
      no_luck?: params["no_luck"] == "true",
      no_risk?: params["no_risk"] == "true",
      clear_liquidity_grab?: params["clear_liquidity_grab"] == "true",
      entry_after_liquidity_grab?: params["entry_after_liquidity_grab"] == "true",
      instant_lose?: params["instant_lose"] == "true",
      too_tight_stop_loss?: params["too_tight_stop_loss"] == "true",
      affected_by_other_trade?: params["affected_by_other_trade"] == "true",
      mid_range?: params["mid_range"] == "true",
      fully_wrong_direction?: params["fully_wrong_direction"] == "true",
      initial_risk_reward_ratio: parse_decimal(params["initial_risk_reward_ratio"]),
      best_risk_reward_ratio:
        if(params["best_rr_enabled"] == "true",
          do: parse_decimal(params["best_risk_reward_ratio"]),
          else: Decimal.new("0")
        ),
      size: parse_decimal(params["size"]),
      close_time_comment: join_close_time_comments(params["close_time_comment"])
    }
  end

  defp parse_string(nil), do: nil
  defp parse_string(""), do: nil
  defp parse_string(str) when is_binary(str), do: String.trim(str)

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp join_close_time_comments(val), do: join_multi_select(val)

  defp join_multi_select(nil), do: nil
  defp join_multi_select([]), do: nil

  defp join_multi_select(list) when is_list(list) do
    joined = list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(", ")
    if joined == "", do: nil, else: joined
  end

  defp join_multi_select(str) when is_binary(str), do: parse_string(str)

  defp build_v3(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      order_type: parse_string(params["order_type"]),
      initial_risk_reward_ratio: parse_decimal(params["initial_risk_reward_ratio"]),
      best_risk_reward_ratio:
        if(params["better_risk_reward_ratio"] == "true",
          do: parse_decimal(params["best_risk_reward_ratio"]),
          else: Decimal.new("0")
        ),
      size_in_r: parse_decimal(params["size_in_r"]),
      r_value: parse_decimal(params["r_value"]),
      # Carried-over boolean flags
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      better_risk_reward_ratio?: params["better_risk_reward_ratio"] == "true",
      choppy_chart?: params["choppy_chart"] == "true",
      close_trade_remorse?: params["close_trade_remorse"] == "true",
      earning_report?: params["earning_report"] == "true",
      follow_up_trial?: params["follow_up_trial"] == "true",
      fully_wrong_direction?: params["fully_wrong_direction"] == "true",
      good_lesson?: params["good_lesson"] == "true",
      hot_sector?: params["hot_sector"] == "true",
      mid_range?: params["mid_range"] == "true",
      news?: params["news"] == "true",
      normal_emotion?: params["normal_emotion"] == "true",
      operation_mistake?: params["operation_mistake"] == "true",
      overnight?: params["overnight"] == "true",
      overnight_in_purpose?: params["overnight_in_purpose"] == "true",
      too_tight_stop_loss?: params["too_tight_stop_loss"] == "true",
      # Renamed boolean flags
      decision_affected_by_other_trade?: params["decision_affected_by_other_trade"] == "true",
      slippage_entry?: params["slippage_entry"] == "true",
      align_ticker_big_picture_trend?: params["align_ticker_big_picture_trend"] == "true",
      align_ticker_intraday_trend?: params["align_ticker_intraday_trend"] == "true",
      # New V3 boolean flags
      adjusted_stoploss?: params["adjusted_stoploss"] == "true",
      adjusted_target?: params["adjusted_target"] == "true",
      align_global_trend?: params["align_global_trend"] == "true",
      align_sector_trend?: params["align_sector_trend"] == "true",
      averaging_down?: params["averaging_down"] == "true",
      averaging_up?: params["averaging_up"] == "true",
      following_trade?: params["following_trade"] == "true",
      following_rule?: params["following_rule"] == "true",
      lack_confidence?: params["lack_confidence"] == "true",
      large_size_in_purpose?: params["large_size_in_purpose"] == "true",
      small_size_in_purpose?: params["small_size_in_purpose"] == "true",
      reasonable_entry_story?: params["reasonable_entry_story"] == "true",
      reasonable_exit_story?: params["reasonable_exit_story"] == "true",
      scalp?: params["scalp"] == "true",
      should_record_obsidian?: params["should_record_obsidian"] == "true",
      size_matching_story?: params["size_matching_story"] == "true",
      too_loose_stop_loss?: params["too_loose_stop_loss"] == "true",
      use_draft_order?: params["use_draft_order"] == "true",
      random_intraday_trend?: params["random_intraday_trend"] == "true",
      auto_calculate_from_winning_trade?: params["auto_calculate_from_winning_trade"] == "true",
      # Multi-select fields
      close_time_comment: join_multi_select(params["close_time_comment"]),
      extra_setup_comment: join_multi_select(params["extra_setup_comment"]),
      good_things: join_multi_select(params["good_things"]),
      patterns: join_multi_select(params["patterns"]),
      regular_lessons: join_multi_select(params["regular_lessons"])
    }
  end
end

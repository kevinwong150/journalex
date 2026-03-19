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

  defp join_close_time_comments(nil), do: nil
  defp join_close_time_comments([]), do: nil

  defp join_close_time_comments(list) when is_list(list) do
    joined = list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(", ")
    if joined == "", do: nil, else: joined
  end

  defp join_close_time_comments(str) when is_binary(str), do: parse_string(str)
end

defmodule JournalexWeb.MetadataParamsBuilderTest do
  use ExUnit.Case, async: true

  alias JournalexWeb.MetadataParamsBuilder

  describe "build/2 with version 1" do
    test "extracts V1 metadata fields from params" do
      params = %{
        "done" => "true",
        "lost_data" => "true",
        "revenge_trade" => "false",
        "fomo" => "false",
        "operation_mistake" => "false",
        "follow_setup" => "true",
        "follow_stop_loss_management" => "true",
        "unnecessary_trade" => "false",
        "rank" => "A",
        "setup" => "ORB",
        "close_trigger" => "Stop Loss",
        "close_time_comment" => ["Good", "Trade", ""]
      }

      result = MetadataParamsBuilder.build(params, 1)

      assert result[:done?] == true
      assert result[:lost_data?] == true
      assert result[:revenge_trade?] == false
      assert result[:follow_setup?] == true
      assert result[:follow_stop_loss_management?] == true
      assert result[:unnecessary_trade?] == false
      assert result[:rank] == "A"
      assert result[:setup] == "ORB"
      assert result[:close_trigger] == "Stop Loss"
      assert result[:close_time_comment] == "Good, Trade"
    end

    test "handles missing fields gracefully" do
      result = MetadataParamsBuilder.build(%{}, 1)
      assert result[:done?] == false
      assert result[:rank] == nil
      assert result[:close_time_comment] == nil
    end

    test "returns empty map for unsupported version" do
      assert MetadataParamsBuilder.build(%{"done" => "true"}, 99) == %{}
    end
  end

  describe "build/2 with version 2" do
    test "extracts V2 metadata fields from params" do
      params = %{
        "done" => "true",
        "lost_data" => "false",
        "revenge_trade" => "false",
        "fomo" => "true",
        "operation_mistake" => "false",
        "rank" => "B",
        "setup" => "FVG",
        "close_trigger" => "Target",
        "initial_risk_reward_ratio" => "2.5",
        "best_rr_enabled" => "true",
        "best_risk_reward_ratio" => "3.0",
        "size" => "1.5",
        "order_type" => "Market",
        "close_time_comment" => ["Nice"],
        # V2 extended booleans
        "add_size" => "true",
        "adjusted_risk_reward" => "false",
        "align_with_trend" => "true",
        "better_risk_reward_ratio" => "false",
        "big_picture" => "false",
        "earning_report" => "false",
        "follow_up_trial" => "false",
        "good_lesson" => "true",
        "hot_sector" => "false",
        "momentum" => "false",
        "news" => "false",
        "normal_emotion" => "true",
        "overnight" => "false",
        "overnight_in_purpose" => "false",
        "slipped_position" => "false",
        "choppychart" => "false",
        "close_trade_remorse" => "false",
        "no_luck" => "false",
        "no_risk" => "false",
        "clear_liquidity_grab" => "false",
        "entry_after_liquidity_grab" => "false",
        "instant_lose" => "false",
        "too_tight_stop_loss" => "false",
        "affected_by_other_trade" => "false",
        "mid_range" => "false",
        "fully_wrong_direction" => "false"
      }

      result = MetadataParamsBuilder.build(params, 2)

      assert result[:done?] == true
      assert result[:fomo?] == true
      assert result[:rank] == "B"
      assert result[:setup] == "FVG"
      assert result[:initial_risk_reward_ratio] == Decimal.new("2.5")
      assert result[:best_risk_reward_ratio] == Decimal.new("3.0")
      assert result[:size] == Decimal.new("1.5")
      assert result[:order_type] == "Market"
      assert result[:close_time_comment] == "Nice"
      assert result[:add_size?] == true
      assert result[:align_with_trend?] == true
      assert result[:good_lesson?] == true
      assert result[:normal_emotion?] == true
      assert result[:momentum?] == false
    end

    test "best_risk_reward_ratio defaults to Decimal 0 when best_rr_enabled is not true" do
      params = %{
        "best_risk_reward_ratio" => "3.0"
      }

      result = MetadataParamsBuilder.build(params, 2)
      assert result[:best_risk_reward_ratio] == Decimal.new("0")
    end

    test "best_risk_reward_ratio is parsed when best_rr_enabled is true" do
      params = %{
        "best_rr_enabled" => "true",
        "best_risk_reward_ratio" => "4.2"
      }

      result = MetadataParamsBuilder.build(params, 2)
      assert result[:best_risk_reward_ratio] == Decimal.new("4.2")
    end

    test "parses blank decimal as nil for initial_risk_reward_ratio" do
      params = %{
        "initial_risk_reward_ratio" => ""
      }

      result = MetadataParamsBuilder.build(params, 2)
      assert result[:initial_risk_reward_ratio] == nil
    end

    test "close_time_comment joins non-empty entries" do
      params = %{
        "close_time_comment" => ["First", "", "Third", "  "]
      }

      result = MetadataParamsBuilder.build(params, 2)
      assert result[:close_time_comment] == "First, Third"
    end
  end

  describe "build/2 with version 3" do
    test "extracts V3 scalar fields from params" do
      params = %{
        "done" => "true",
        "lost_data" => "false",
        "rank" => "A Trade",
        "setup" => "Reversal - Day High/Low",
        "close_trigger" => "Automatically - Take Profit",
        "order_type" => "Limit Order",
        "target_progress" => "50%",
        "stoploss_progress" => "25%",
        "initial_risk_reward_ratio" => "2.0",
        "best_rr_enabled" => "true",
        "best_risk_reward_ratio" => "3.5",
        "size_in_r" => "1.2",
        "r_value" => "150.00"
      }

      result = MetadataParamsBuilder.build(params, 3)

      assert result[:done?] == true
      assert result[:lost_data?] == false
      assert result[:rank] == "A Trade"
      assert result[:setup] == "Reversal - Day High/Low"
      assert result[:close_trigger] == "Automatically - Take Profit"
      assert result[:order_type] == "Limit Order"
      assert result[:target_progress] == "50%"
      assert result[:stoploss_progress] == "25%"
      assert result[:initial_risk_reward_ratio] == Decimal.new("2.0")
      assert result[:best_risk_reward_ratio] == Decimal.new("3.5")
      assert result[:size_in_r] == Decimal.new("1.2")
      assert result[:r_value] == Decimal.new("150.00")
    end

    test "extracts V3 boolean flags" do
      params = %{
        "align_global_trend" => "true",
        "align_sector_trend" => "false",
        "choppy_chart" => "true",
        "revenge_trade" => "false",
        "fomo" => "true",
        "scalp" => "true",
        "should_record_obsidian" => "false",
        "averaging_up" => "true",
        "averaging_down" => "false"
      }

      result = MetadataParamsBuilder.build(params, 3)

      assert result[:align_global_trend?] == true
      assert result[:align_sector_trend?] == false
      assert result[:choppy_chart?] == true
      assert result[:revenge_trade?] == false
      assert result[:fomo?] == true
      assert result[:scalp?] == true
      assert result[:should_record_obsidian?] == false
      assert result[:averaging_up?] == true
      assert result[:averaging_down?] == false
    end

    test "extracts V3 multi-select fields" do
      params = %{
        "close_time_comment" => ["Consider stop loss", "Will hit stop loss if not close"],
        "extra_setup_comment" => ["Straight losing"],
        "good_things" => ["Good spotting setup", "Good execution"],
        "patterns" => ["Lead Lag"],
        "regular_lessons" => ["Discipline"]
      }

      result = MetadataParamsBuilder.build(params, 3)

      assert result[:close_time_comment] == "Consider stop loss, Will hit stop loss if not close"
      assert result[:extra_setup_comment] == "Straight losing"
      assert result[:good_things] == "Good spotting setup, Good execution"
      assert result[:patterns] == "Lead Lag"
      assert result[:regular_lessons] == "Discipline"
    end

    test "best_risk_reward_ratio defaults to 0 when best_rr_enabled not set" do
      result = MetadataParamsBuilder.build(%{"best_risk_reward_ratio" => "2.0"}, 3)
      assert result[:best_risk_reward_ratio] == Decimal.new("0")
    end

    test "handles empty V3 params gracefully" do
      result = MetadataParamsBuilder.build(%{}, 3)
      assert result[:done?] == false
      assert result[:rank] == nil
      assert result[:initial_risk_reward_ratio] == nil
      assert result[:close_time_comment] == nil
    end
  end
end

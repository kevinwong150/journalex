defmodule Journalex.Trades.Metadata.V3Test do
  use ExUnit.Case, async: true

  alias Journalex.Trades.Metadata.V3

  describe "changeset/2 — boolean flags" do
    test "all boolean flags default to false" do
      changeset = V3.changeset(%V3{}, %{})
      assert changeset.valid?

      metadata = Ecto.Changeset.apply_changes(changeset)

      # Status
      assert metadata.done? == false
      assert metadata.lost_data? == false

      # Carried from V2
      assert metadata.fomo? == false
      assert metadata.revenge_trade? == false
      assert metadata.choppy_chart? == false

      # New V3 flags
      assert metadata.align_global_trend? == false
      assert metadata.align_sector_trend? == false
      assert metadata.scalp? == false
      assert metadata.should_record_obsidian? == false
    end

    test "sets boolean flags from attrs" do
      attrs = %{
        done?: true,
        align_global_trend?: true,
        fomo?: true,
        choppy_chart?: true,
        scalp?: true
      }

      changeset = V3.changeset(%V3{}, attrs)
      assert changeset.valid?

      metadata = Ecto.Changeset.apply_changes(changeset)
      assert metadata.done? == true
      assert metadata.align_global_trend? == true
      assert metadata.fomo? == true
      assert metadata.choppy_chart? == true
      assert metadata.scalp? == true
    end
  end

  describe "changeset/2 — enum validations" do
    test "valid rank values are accepted" do
      for rank <- ["Not Setup", "Bad Setup", "C Trade", "B Trade", "A Trade"] do
        changeset = V3.changeset(%V3{}, %{rank: rank})
        assert changeset.valid?, "Expected rank '#{rank}' to be valid"
      end
    end

    test "invalid rank is rejected" do
      changeset = V3.changeset(%V3{}, %{rank: "BAD Trade"})
      refute changeset.valid?
      assert {_msg, _} = changeset.errors[:rank]
    end

    test "nil rank is valid (not required)" do
      changeset = V3.changeset(%V3{}, %{rank: nil})
      assert changeset.valid?
    end

    test "valid setup values are accepted" do
      for setup <- [
        "Bouncy Ball - Big Seller/Buyer",
        "Breakout - Day High/Low",
        "Reversal - Capitulation",
        "Reversal - Day High/Low",
        "Reversal - Pullback Reversal",
        "Testing Setup",
        "Not Setup"
      ] do
        changeset = V3.changeset(%V3{}, %{setup: setup})
        assert changeset.valid?, "Expected setup '#{setup}' to be valid"
      end
    end

    test "invalid setup is rejected" do
      changeset = V3.changeset(%V3{}, %{setup: "Trend Continuation - MACD"})
      refute changeset.valid?
    end

    test "valid close_trigger values are accepted" do
      for ct <- [
        "Automatically - Take Profit",
        "Automatically - Stop Loss",
        "Manually - Take Profit",
        "Manually - Stop Loss",
        "Manually - Reverse",
        "Automatically - Breakeven"
      ] do
        changeset = V3.changeset(%V3{}, %{close_trigger: ct})
        assert changeset.valid?, "Expected close_trigger '#{ct}' to be valid"
      end
    end

    test "valid order_type values are accepted" do
      for ot <- ["Limit Order", "Stop Order", "Market Order"] do
        changeset = V3.changeset(%V3{}, %{order_type: ot})
        assert changeset.valid?, "Expected order_type '#{ot}' to be valid"
      end
    end

    test "valid target_progress values" do
      for v <- ["25%", "50%", "75%"] do
        changeset = V3.changeset(%V3{}, %{target_progress: v})
        assert changeset.valid?, "Expected target_progress '#{v}' to be valid"
      end
    end

    test "invalid target_progress is rejected" do
      changeset = V3.changeset(%V3{}, %{target_progress: "100%"})
      refute changeset.valid?
    end

    test "valid stoploss_progress values" do
      for v <- ["25%", "50%", "75%"] do
        changeset = V3.changeset(%V3{}, %{stoploss_progress: v})
        assert changeset.valid?
      end
    end
  end

  describe "changeset/2 — decimal fields" do
    test "accepts decimal values for risk/reward fields" do
      attrs = %{
        initial_risk_reward_ratio: Decimal.new("2.5"),
        best_risk_reward_ratio: Decimal.new("3.0"),
        size_in_r: Decimal.new("1.2"),
        r_value: Decimal.new("150.00")
      }

      changeset = V3.changeset(%V3{}, attrs)
      assert changeset.valid?

      metadata = Ecto.Changeset.apply_changes(changeset)
      assert Decimal.equal?(metadata.initial_risk_reward_ratio, Decimal.new("2.5"))
      assert Decimal.equal?(metadata.best_risk_reward_ratio, Decimal.new("3.0"))
      assert Decimal.equal?(metadata.size_in_r, Decimal.new("1.2"))
      assert Decimal.equal?(metadata.r_value, Decimal.new("150.00"))
    end
  end

  describe "changeset/2 — multi-select string fields" do
    test "accepts string values for multi-select fields" do
      attrs = %{
        close_time_comment: "Consider stop loss, Will hit stop loss if not close",
        extra_setup_comment: "Straight losing",
        good_things: "Good spotting setup, Good execution",
        patterns: "Lead Lag",
        regular_lessons: "Discipline"
      }

      changeset = V3.changeset(%V3{}, attrs)
      assert changeset.valid?

      metadata = Ecto.Changeset.apply_changes(changeset)
      assert metadata.close_time_comment == "Consider stop loss, Will hit stop loss if not close"
      assert metadata.extra_setup_comment == "Straight losing"
    end
  end

  describe "changeset/2 — empty changeset" do
    test "empty attrs produces a valid changeset with all defaults" do
      changeset = V3.changeset(%V3{}, %{})
      assert changeset.valid?
    end
  end
end

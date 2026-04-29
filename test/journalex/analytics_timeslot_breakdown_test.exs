defmodule Journalex.AnalyticsTimeslotBreakdownTest do
  use Journalex.DataCase, async: true

  alias Journalex.Analytics
  alias Journalex.Repo
  alias Journalex.Trades.Trade

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp base_trade(overrides \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Map.merge(
      %{
        datetime: now,
        ticker: "AAPL",
        aggregated_side: "LONG",
        result: "WIN",
        realized_pl: Decimal.new("8.00"),
        action_chain: %{},
        metadata_version: 2,
        metadata: %{
          "done?" => true,
          "entry_timeslot" => "0930-1000",
          "close_timeslot" => "1000-1030"
        }
      },
      overrides
    )
  end

  defp insert_trade(overrides \\ %{}) do
    %Trade{}
    |> Trade.changeset(base_trade(overrides))
    |> Repo.insert!()
  end

  # ---------------------------------------------------------------------------
  # timeslot_breakdown(:entry_timeslot, opts)
  # ---------------------------------------------------------------------------

  describe "timeslot_breakdown(:entry_timeslot)" do
    test "returns empty list when no trades" do
      assert Analytics.timeslot_breakdown(:entry_timeslot) == []
    end

    test "returns {ts, total_r, avg_r, wins, losses} 5-tuples" do
      insert_trade(%{result: "WIN", realized_pl: Decimal.new("8.00"),
                     metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})

      [result] = Analytics.timeslot_breakdown(:entry_timeslot)
      assert {ts, total_r, avg_r, wins, losses} = result
      assert ts == "0930-1000"
      assert is_float(total_r)
      assert is_float(avg_r)
      assert is_integer(wins)
      assert is_integer(losses)
    end

    test "counts wins and losses correctly" do
      insert_trade(%{result: "WIN", realized_pl: Decimal.new("8.00"),
                     metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})
      insert_trade(%{result: "WIN", realized_pl: Decimal.new("16.00"),
                     metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})
      insert_trade(%{result: "LOSE", realized_pl: Decimal.new("-8.00"),
                     metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})

      [{"0930-1000", total_r, _avg_r, wins, losses}] =
        Analytics.timeslot_breakdown(:entry_timeslot)

      assert wins == 2
      assert losses == 1
      assert total_r > 0
    end

    test "groups by timeslot and sorts ascending" do
      insert_trade(%{metadata: %{"done?" => true, "entry_timeslot" => "1300-1330"}})
      insert_trade(%{metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})
      insert_trade(%{metadata: %{"done?" => true, "entry_timeslot" => "1000-1030"}})

      results = Analytics.timeslot_breakdown(:entry_timeslot)
      slots = Enum.map(results, fn {ts, _, _, _, _} -> ts end)
      assert slots == Enum.sort(slots)
      assert length(results) == 3
    end

    test "excludes trades where done? is false" do
      insert_trade(%{metadata: %{"done?" => false, "entry_timeslot" => "0930-1000"}})

      assert Analytics.timeslot_breakdown(:entry_timeslot) == []
    end

    test "excludes trades without entry_timeslot field" do
      insert_trade(%{metadata: %{"done?" => true}})

      assert Analytics.timeslot_breakdown(:entry_timeslot) == []
    end

    test "respects versions filter" do
      insert_trade(%{metadata_version: 1,
                     metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})
      insert_trade(%{metadata_version: 2,
                     metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}})

      results = Analytics.timeslot_breakdown(:entry_timeslot, versions: [2])
      assert length(results) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # timeslot_breakdown(:close_timeslot, opts)
  # ---------------------------------------------------------------------------

  describe "timeslot_breakdown(:close_timeslot)" do
    test "returns empty list when no trades" do
      assert Analytics.timeslot_breakdown(:close_timeslot) == []
    end

    test "V1 trades (no close_timeslot field) do not appear in results" do
      insert_trade(%{
        metadata_version: 1,
        metadata: %{"done?" => true, "entry_timeslot" => "0930-1000"}
      })

      assert Analytics.timeslot_breakdown(:close_timeslot) == []
    end

    test "V2 trades with close_timeslot appear in results" do
      insert_trade(%{
        metadata_version: 2,
        metadata: %{"done?" => true, "entry_timeslot" => "0930-1000", "close_timeslot" => "1000-1030"}
      })

      assert [{"1000-1030", _, _, _, _}] = Analytics.timeslot_breakdown(:close_timeslot)
    end
  end
end

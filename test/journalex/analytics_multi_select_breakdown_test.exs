defmodule Journalex.AnalyticsMultiSelectBreakdownTest do
  use Journalex.DataCase, async: true

  alias Journalex.Analytics
  alias Journalex.Repo
  alias Journalex.Trades.Trade

  defp base_trade(overrides) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Map.merge(
      %{
        datetime: now,
        ticker: "AAPL",
        aggregated_side: "LONG",
        result: "WIN",
        realized_pl: Decimal.new("8.00"),
        action_chain: %{},
        metadata_version: 3,
        metadata: %{
          "done?" => true,
          "patterns" => "breakout, momentum",
          "regular_lessons" => "setup, review"
        }
      },
      overrides
    )
  end

  defp insert_trade(overrides) do
    %Trade{}
    |> Trade.changeset(base_trade(overrides))
    |> Repo.insert!()
  end

  describe "multi_select_breakdown/2" do
    test "splits comma-separated values into multiple buckets" do
      insert_trade(%{
        result: "WIN",
        realized_pl: Decimal.new("8.00"),
        metadata: %{
          "done?" => true,
          "patterns" => "breakout, momentum"
        }
      })

      insert_trade(%{
        result: "LOSE",
        realized_pl: Decimal.new("-4.00"),
        metadata: %{
          "done?" => true,
          "patterns" => "momentum"
        }
      })

      results = Analytics.multi_select_breakdown(:patterns, r_size: 1.0)

      assert [
               {"breakout", 8.0, 1.0, 1},
               {"momentum", 4.0, 0.5, 2}
             ] = results
    end

    test "trims whitespace and ignores blank segments" do
      insert_trade(%{
        metadata: %{
          "done?" => true,
          "regular_lessons" => "  setup , ,  review  ,  "
        }
      })

      results = Analytics.multi_select_breakdown(:regular_lessons, r_size: 1.0)

      assert Enum.map(results, fn {label, _, _, _} -> label end) |> Enum.sort() == ["review", "setup"]
      assert Enum.all?(results, fn {_, _, _, count} -> count == 1 end)
    end

    test "excludes trades where done? is false" do
      insert_trade(%{
        metadata: %{
          "done?" => false,
          "patterns" => "breakout"
        }
      })

      assert Analytics.multi_select_breakdown(:patterns) == []
    end
  end
end

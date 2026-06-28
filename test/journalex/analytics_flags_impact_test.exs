defmodule Journalex.AnalyticsFlagsImpactTest do
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
        metadata: %{"done?" => true}
      },
      overrides
    )
  end

  defp insert_trade(overrides) do
    %Trade{}
    |> Trade.changeset(base_trade(overrides))
    |> Repo.insert!()
  end

  defp find_flag!(flags, name) do
    Enum.find_value(flags, fn
      {^name, avg_on, avg_off, count_on, count_off} -> {avg_on, avg_off, count_on, count_off}
      _ -> nil
    end) || raise "flag #{name} not found in #{inspect(flags)}"
  end

  describe "flags_impact/1" do
    test "includes V3-only flags and compares OFF rows within the same supported version only" do
      insert_trade(%{
        ticker: "V3ON",
        result: "LOSE",
        realized_pl: Decimal.new("-8.00"),
        metadata_version: 3,
        metadata: %{
          "done?" => true,
          "following_rule?" => true
        }
      })

      insert_trade(%{
        ticker: "V3OFF",
        result: "WIN",
        realized_pl: Decimal.new("8.00"),
        metadata_version: 3,
        metadata: %{
          "done?" => true,
          "following_rule?" => false
        }
      })

      insert_trade(%{
        ticker: "V2NOISE",
        result: "WIN",
        realized_pl: Decimal.new("80.00"),
        metadata_version: 2,
        metadata: %{
          "done?" => true,
          "revenge_trade?" => false
        }
      })

      flags = Analytics.flags_impact(versions: [2, 3], r_size: 8.0)

      assert {-1.0, 1.0, 1, 1} = find_flag!(flags, "following_rule?")
    end

    test "recognizes renamed V3 flags by their V3 key names" do
      insert_trade(%{
        ticker: "RENAMEDV3",
        result: "LOSE",
        realized_pl: Decimal.new("-8.00"),
        metadata_version: 3,
        metadata: %{
          "done?" => true,
          "slippage_entry?" => true
        }
      })

      flags = Analytics.flags_impact(versions: [3], r_size: 8.0)

      assert {avg_on, avg_off, count_on, count_off} = find_flag!(flags, "slippage_entry?")
      assert avg_on == -1.0
      assert avg_off == 0.0
      assert count_on == 1
      assert count_off == 0
      refute Enum.any?(flags, fn {flag, _, _, _, _} -> flag == "slipped_position?" end)
    end
  end

  describe "scorecard_periods/2" do
    test "can surface a V3-only flag as the top flag for a period" do
      dt = ~U[2026-06-03 14:00:00Z]

      insert_trade(%{
        datetime: dt,
        ticker: "FLAG1",
        metadata_version: 3,
        metadata: %{
          "done?" => true,
          "following_rule?" => true
        }
      })

      insert_trade(%{
        datetime: DateTime.add(dt, 60, :second),
        ticker: "FLAG2",
        metadata_version: 3,
        metadata: %{
          "done?" => true,
          "following_rule?" => true
        }
      })

      [row] = Analytics.scorecard_periods(:month, versions: [3], r_size: 8.0)

      assert row.top_flag == "following_rule?"
    end
  end
end

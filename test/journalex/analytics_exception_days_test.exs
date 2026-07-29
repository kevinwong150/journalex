defmodule Journalex.AnalyticsExceptionDaysTest do
  use Journalex.DataCase, async: true

  alias Journalex.Analytics
  alias Journalex.Repo
  alias Journalex.Settings
  alias Journalex.Trades.Trade

  defp base_trade(overrides) do
    Map.merge(
      %{
        datetime: ~U[2026-06-01 14:00:00Z],
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

  test "kpi_summary excludes configured exception days from the shared base query" do
    assert {:ok, _} = Settings.set_analytics_exception_days(["2026-06-01"])

    insert_trade(%{
      ticker: "EXCLUDED",
      datetime: ~U[2026-06-01 14:00:00Z],
      result: "LOSE",
      realized_pl: Decimal.new("-8.00")
    })

    insert_trade(%{
      ticker: "INCLUDED",
      datetime: ~U[2026-06-02 14:00:00Z],
      result: "WIN",
      realized_pl: Decimal.new("8.00")
    })

    summary = Analytics.kpi_summary(versions: [3], r_size: 8.0)

    assert summary.trade_count == 1
    assert summary.total_r == 1.0
    assert summary.best_r == 1.0
    assert summary.worst_r == 1.0
  end
end
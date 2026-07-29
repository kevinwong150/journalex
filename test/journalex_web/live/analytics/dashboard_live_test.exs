defmodule JournalexWeb.Analytics.DashboardLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Journalex.Repo
  alias Journalex.Settings
  alias Journalex.Trades.Trade

  defp insert_trade(datetime, ticker, result, realized_pl) do
    %Trade{}
    |> Trade.changeset(%{
      datetime: datetime,
      ticker: ticker,
      aggregated_side: "LONG",
      result: result,
      realized_pl: Decimal.new(realized_pl),
      action_chain: %{},
      metadata_version: 3,
      metadata: %{"done?" => true}
    })
    |> Repo.insert!()
  end

  setup do
    on_exit(fn -> Settings.set_analytics_exception_days([]) end)
    :ok
  end

  test "shows exception days and toggles exclusion on the dashboard", %{conn: conn} do
    Settings.set_analytics_exception_days(["2026-06-01"])

    insert_trade(~U[2026-06-01 14:00:00Z], "EXCLUDED", "WIN", "8.00")
    insert_trade(~U[2026-06-02 14:00:00Z], "INCLUDED", "WIN", "8.00")

    {:ok, view, html} = live(conn, ~p"/analytics/dashboard")

    assert html =~ "Exception days:"
    assert html =~ "2026-06-01"
    assert html =~ "Excluding exception days"

    html = render_click(view, "toggle_exception_days")

    assert html =~ "Including exception days"
  end
end

defmodule Journalex.ActivityTest do
  use Journalex.DataCase, async: true

  alias Journalex.Activity
  alias Journalex.ActivityStatementParser, as: Parser
  import Journalex.TestFixtures

  # ── dedupe_by_datetime_symbol/1 ──

  describe "dedupe_by_datetime_symbol/1" do
    test "removes duplicate (datetime, symbol) pairs" do
      rows = [
        %{datetime: "2026-02-04 12:20:32", symbol: "COIN", quantity: "-8"},
        %{datetime: "2026-02-04 12:20:32", symbol: "COIN", quantity: "-8"},
        %{datetime: "2026-02-04 12:38:46", symbol: "COIN", quantity: "8"}
      ]

      result = Activity.dedupe_by_datetime_symbol(rows)
      assert length(result) == 2
    end

    test "preserves rows with different datetimes" do
      rows = [
        %{datetime: "2026-02-04 12:20:32", symbol: "COIN"},
        %{datetime: "2026-02-04 12:38:46", symbol: "COIN"}
      ]

      assert length(Activity.dedupe_by_datetime_symbol(rows)) == 2
    end

    test "preserves rows with different symbols" do
      rows = [
        %{datetime: "2026-02-04 12:20:32", symbol: "COIN"},
        %{datetime: "2026-02-04 12:20:32", symbol: "META"}
      ]

      assert length(Activity.dedupe_by_datetime_symbol(rows)) == 2
    end

    test "non-list input returns empty list" do
      assert Activity.dedupe_by_datetime_symbol(nil) == []
    end

    test "empty list returns empty list" do
      assert Activity.dedupe_by_datetime_symbol([]) == []
    end
  end

  # ── save_activity_rows/1 ──

  describe "save_activity_rows/1" do
    test "inserts parsed trades from fixture CSV" do
      trades = Parser.parse_trades_file(single_ticker_csv())
      assert {:ok, count} = Activity.save_activity_rows(trades)
      assert count == 2
    end

    test "is idempotent (second call inserts 0)" do
      trades = Parser.parse_trades_file(single_ticker_csv())
      assert {:ok, 2} = Activity.save_activity_rows(trades)
      assert {:ok, 0} = Activity.save_activity_rows(trades)
    end

    test "inserts multi-ticker trades" do
      trades = Parser.parse_trades_file(multi_ticker_csv())
      assert {:ok, count} = Activity.save_activity_rows(trades)
      assert count == 11
    end

    test "empty list inserts nothing" do
      assert {:ok, 0} = Activity.save_activity_rows([])
    end
  end

  # ── save_activity_row/1 ──

  describe "save_activity_row/1" do
    test "inserts a single parsed trade" do
      [trade | _] = Parser.parse_trades_file(single_ticker_csv())
      assert {:ok, struct} = Activity.save_activity_row(trade)
      refute struct == :exists
    end

    test "returns :exists for duplicate row" do
      [trade | _] = Parser.parse_trades_file(single_ticker_csv())
      assert {:ok, _} = Activity.save_activity_row(trade)
      assert {:ok, :exists} = Activity.save_activity_row(trade)
    end
  end

  # ── rows_exist_flags/1 ──

  describe "rows_exist_flags/1" do
    test "returns false flags for unsaved rows" do
      trades = Parser.parse_trades_file(single_ticker_csv())
      flags = Activity.rows_exist_flags(trades)
      assert length(flags) == 2
      assert Enum.all?(flags, &(&1 == false))
    end

    test "returns true flags for saved rows" do
      trades = Parser.parse_trades_file(single_ticker_csv())
      Activity.save_activity_rows(trades)
      flags = Activity.rows_exist_flags(trades)
      assert Enum.all?(flags, &(&1 == true))
    end
  end

  # ── list_activity_statements_between/3 ──

  describe "list_activity_statements_between/3" do
    setup do
      # Insert multi-ticker trades spanning Feb 9
      trades = Parser.parse_trades_file(multi_ticker_csv())
      {:ok, _} = Activity.save_activity_rows(trades)
      :ok
    end

    test "returns rows within date range" do
      results = Activity.list_activity_statements_between(~D[2026-02-09], ~D[2026-02-09])
      assert length(results) == 11
    end

    test "returns empty for out-of-range dates" do
      results = Activity.list_activity_statements_between(~D[2026-03-01], ~D[2026-03-31])
      assert results == []
    end

    test "filters by symbol option" do
      results =
        Activity.list_activity_statements_between(~D[2026-02-09], ~D[2026-02-09], symbol: "CRM")

      assert length(results) == 2
      assert Enum.all?(results, &(&1.symbol == "CRM"))
    end

    test "filters by symbol — JPM returns 4 rows" do
      results =
        Activity.list_activity_statements_between(~D[2026-02-09], ~D[2026-02-09], symbol: "JPM")

      assert length(results) == 4
    end
  end
end

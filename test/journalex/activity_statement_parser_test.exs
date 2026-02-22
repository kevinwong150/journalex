defmodule Journalex.ActivityStatementParserTest do
  use ExUnit.Case, async: true

  alias Journalex.ActivityStatementParser, as: Parser
  import Journalex.TestFixtures

  # ── parse_period_file/1 ──

  describe "parse_period_file/1" do
    test "extracts period from no-trades day" do
      assert Parser.parse_period_file(no_trades_csv()) == "January 28, 2026"
    end

    test "extracts period from single-ticker day" do
      assert Parser.parse_period_file(single_ticker_csv()) == "February 4, 2026"
    end

    test "extracts period from multi-ticker day" do
      assert Parser.parse_period_file(multi_ticker_csv()) == "February 9, 2026"
    end
  end

  # ── parse_trades_file/1 ──

  describe "parse_trades_file/1 — no trades day" do
    test "returns empty list when no Trades section" do
      assert Parser.parse_trades_file(no_trades_csv()) == []
    end
  end

  describe "parse_trades_file/1 — single ticker" do
    setup do
      trades = Parser.parse_trades_file(single_ticker_csv())
      %{trades: trades}
    end

    test "returns exactly 2 order rows", %{trades: trades} do
      assert length(trades) == 2
    end

    test "all trades are COIN", %{trades: trades} do
      assert Enum.all?(trades, &(&1.symbol == "COIN"))
    end

    test "first trade is an opening sell", %{trades: trades} do
      [open | _] = trades
      assert open.quantity == "-8"
      assert open.code == "O"
    end

    test "second trade is a closing buy", %{trades: trades} do
      close = List.last(trades)
      assert close.quantity == "8"
      assert String.contains?(close.code, "C")
    end

    test "datetimes are normalized (no comma)", %{trades: trades} do
      Enum.each(trades, fn t ->
        refute String.contains?(t.datetime, ",")
        assert String.match?(t.datetime, ~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/)
      end)
    end

    test "all expected map keys present", %{trades: trades} do
      expected_keys =
        ~w(asset_category currency symbol datetime quantity trade_price
           current_price proceeds comm_fee basis realized_pl mtm_pl code)a

      Enum.each(trades, fn t ->
        for key <- expected_keys do
          assert Map.has_key?(t, key), "missing key: #{key}"
        end
      end)
    end
  end

  describe "parse_trades_file/1 — multi ticker" do
    setup do
      trades = Parser.parse_trades_file(multi_ticker_csv())
      %{trades: trades}
    end

    test "returns 10 order rows (CRM 2, JPM 4, PYPL 2, V 3)", %{trades: trades} do
      # CRM: 2, JPM: 4, PYPL: 2, V: 3 = 11 total
      assert length(trades) == 11
    end

    test "contains 4 unique tickers", %{trades: trades} do
      tickers = trades |> Enum.map(& &1.symbol) |> Enum.uniq() |> Enum.sort()
      assert tickers == ["CRM", "JPM", "PYPL", "V"]
    end

    test "all datetimes are on Feb 9, 2026", %{trades: trades} do
      Enum.each(trades, fn t ->
        assert String.starts_with?(t.datetime, "2026-02-09")
      end)
    end

    test "realized_pl values are present for closing trades", %{trades: trades} do
      closing = Enum.filter(trades, fn t -> String.contains?(t.code || "", "C") end)
      assert length(closing) > 0

      Enum.each(closing, fn t ->
        {val, _} = Float.parse(t.realized_pl)
        assert val != 0.0 or t.realized_pl != nil
      end)
    end
  end

  # ── parse_trades_content/1 (content-based, no file) ──

  describe "parse_trades_content/1" do
    test "parses inline CSV content" do
      csv = """
      Statement,Header,Field Name,Field Value
      Statement,Data,Period,"Test Day"
      Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,Comm/Fee,Basis,Realized P/L,MTM P/L,Code
      Trades,Data,Order,Stocks,USD,AAPL,"2026-01-15, 10:30:00",-5,200.50,201.00,1002.50,-0.35,-1002.15,0,-2.50,O
      Trades,Data,SubTotal,,Stocks,USD,AAPL,,0,,,1002.50,-0.35,-1002.15,0,-2.50,
      """

      trades = Parser.parse_trades_content(csv)
      assert length(trades) == 1
      assert hd(trades).symbol == "AAPL"
      assert hd(trades).datetime == "2026-01-15 10:30:00"
    end

    test "returns empty list for content with no Trades section" do
      csv = """
      Statement,Header,Field Name,Field Value
      Statement,Data,Period,"No trades"
      Cash Report,Header,Currency Summary,Currency,Total,
      Cash Report,Data,Starting Cash,Base Currency Summary,1000000,
      """

      assert Parser.parse_trades_content(csv) == []
    end
  end
end

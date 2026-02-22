defmodule Journalex.TradesTest do
  use Journalex.DataCase, async: true

  alias Journalex.Trades

  # ── upsert_trade_rows/1 ──

  describe "upsert_trade_rows/1" do
    test "inserts trade rows" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows = [
        %{
          datetime: now,
          ticker: "COIN",
          aggregated_side: "SHORT",
          result: "WIN",
          realized_pl: Decimal.new("21.95"),
          duration: 1094,
          action_chain: %{},
          inserted_at: now,
          updated_at: now
        }
      ]

      assert {1, _} = Trades.upsert_trade_rows(rows)
    end

    test "is idempotent (duplicate key → no insert)" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      row = %{
        datetime: now,
        ticker: "META",
        aggregated_side: "LONG",
        result: "LOSE",
        realized_pl: Decimal.new("-0.20"),
        duration: 516,
        action_chain: %{},
        inserted_at: now,
        updated_at: now
      }

      assert {1, _} = Trades.upsert_trade_rows([row])
      assert {0, _} = Trades.upsert_trade_rows([row])
    end

    test "empty list → {0, nil}" do
      assert {0, nil} = Trades.upsert_trade_rows([])
    end
  end

  # ── persisted_trade_keys/3 ──

  describe "persisted_trade_keys/3" do
    test "returns empty set when no trades" do
      keys = Trades.persisted_trade_keys(~D[2026-02-01], ~D[2026-02-28], ["COIN"])
      assert MapSet.size(keys) == 0
    end

    test "returns matching keys after insert" do
      now = DateTime.new!(~D[2026-02-04], ~T[12:20:32], "Etc/UTC")

      row = %{
        datetime: now,
        ticker: "COIN",
        aggregated_side: "SHORT",
        result: "WIN",
        realized_pl: Decimal.new("21.95"),
        duration: 1094,
        action_chain: %{},
        inserted_at: now,
        updated_at: now
      }

      Trades.upsert_trade_rows([row])

      keys = Trades.persisted_trade_keys(~D[2026-02-01], ~D[2026-02-28], ["COIN"])
      assert MapSet.size(keys) == 1
      assert MapSet.member?(keys, {"2026-02-04", "COIN", "SHORT", 21.95})
    end

    test "does not return keys for other tickers" do
      now = DateTime.new!(~D[2026-02-04], ~T[12:20:32], "Etc/UTC")

      row = %{
        datetime: now,
        ticker: "COIN",
        aggregated_side: "SHORT",
        result: "WIN",
        realized_pl: Decimal.new("21.95"),
        duration: 1094,
        action_chain: %{},
        inserted_at: now,
        updated_at: now
      }

      Trades.upsert_trade_rows([row])

      keys = Trades.persisted_trade_keys(~D[2026-02-01], ~D[2026-02-28], ["META"])
      assert MapSet.size(keys) == 0
    end
  end
end

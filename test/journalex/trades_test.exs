defmodule Journalex.TradesTest do
  use Journalex.DataCase, async: true

  alias Journalex.Trades
  alias Journalex.Trades.Trade
  import Ecto.Query

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

  # ── journal_data / update_trade with journal_data ──

  describe "update_trade/2 with journal_data" do
    setup do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      row = %{
        datetime: now,
        ticker: "AAPL",
        aggregated_side: "LONG",
        result: "WIN",
        realized_pl: Decimal.new("50.00"),
        duration: 300,
        action_chain: %{},
        inserted_at: now,
        updated_at: now
      }

      {1, _} = Trades.upsert_trade_rows([row])

      trade =
        Journalex.Repo.one!(
          from(t in Trade,
            where: t.ticker == "AAPL" and t.aggregated_side == "LONG",
            limit: 1
          )
        )

      {:ok, trade: trade}
    end

    test "saves progression_chain in journal_data", %{trade: trade} do
      {:ok, updated} = Trades.update_trade(trade, %{
        journal_data: %{"progression_chain" => ["ENTRY", "W25", "TARGET"]}
      })

      assert updated.journal_data["progression_chain"] == ["ENTRY", "W25", "TARGET"]
    end

    test "journal_data defaults to empty map on new trade", %{trade: trade} do
      assert trade.journal_data == %{}
    end

    test "journal_data can be cleared to empty map", %{trade: trade} do
      {:ok, updated} = Trades.update_trade(trade, %{
        journal_data: %{"progression_chain" => ["ENTRY"]}
      })

      {:ok, cleared} = Trades.update_trade(updated, %{journal_data: %{}})
      assert cleared.journal_data == %{}
    end
  end
end

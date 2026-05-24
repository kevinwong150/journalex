---
applyTo: "test/**"
---

# Testing conventions — Journalex

## Test case selection

| What you're testing | Use |
|---|---|
| Context functions / schemas / DB | `use Journalex.DataCase` |
| HTTP controllers | `use JournalexWeb.ConnCase` |
| LiveViews | `use JournalexWeb.ConnCase` + `import Phoenix.LiveViewTest` |
| Pure functions, no DB | `use ExUnit.Case, async: true` |

## Mox mocks (available but not widely used yet)

Six Mox mocks are defined in `test/test_helper.exs`:
- `Journalex.MockActivity` for `Journalex.ActivityBehaviour`
- `Journalex.MockTrades` for `Journalex.TradesBehaviour`
- `Journalex.MockSettings` for `Journalex.SettingsBehaviour`
- `Journalex.MockParser` for `Journalex.ParserBehaviour`
- `Journalex.MockWriteupDrafts` for `Journalex.WriteupDraftsBehaviour`
- `Journalex.MockCombinedDrafts` for `Journalex.CombinedDraftsBehaviour`

Currently, the existing LiveView test (`ActivityStatementUploadResultLiveTest`) calls real modules with CSV fixtures and a real DB — it does **not** use Mox. Context unit tests also call real implementations.

- `Mox.expect/3` — function MUST be called exactly once
- `Mox.stub/3` — function may be called zero or more times
- Always call `verify_on_exit!` if using Mox

## Assert patterns

```elixir
assert {:ok, result} = Context.function(args)
assert {:error, changeset} = Context.function(bad_args)
assert %{field: ["can't be blank"]} = errors_on(changeset)
```

## JSONB string-key assertions

After loading from DB, JSONB fields return **string keys**:

```elixir
assert trade.metadata["done?"] == true   # ✅ correct
assert trade.metadata.done? == true      # ❌ wrong
```

## Trade fixture pattern (context/Analytics tests)

No shared fixture helper exists for `Trade` records. Create them inline using `Map.merge/2` for base+overrides:

```elixir
base = %{
  symbol: "NQ", open_date_time: ~N[2025-01-01 09:30:00], ...,
  metadata_version: 2,
  metadata: %{"done?" => true, "entry_timeslot" => "09:30"}
}

%Trade{} |> Trade.changeset(Map.merge(base, %{metadata: %{...}})) |> Repo.insert!()
```

- Always use string keys in the `metadata` map (JSONB is stored and read back with string keys)
- Override only the fields that differ per test case

## CSV fixtures

Use only helpers from `test/support/fixtures.ex`. Do NOT read arbitrary file paths directly.

## File placement

Test files go under `test/journalex/` mirroring the path in `lib/journalex/`.

## Upsert and post-insert fetching

`Trades.upsert_trade_rows/1` does **not** support `returning: true`. After calling it in tests, fetch the inserted record with `Repo.one!` + `Ecto.Query`:

```elixir
import Ecto.Query
trade = Repo.one!(from t in Trade, where: t.ibkr_trade_id == ^id)
```

Never assume a `{:ok, trade}` tuple from `upsert_trade_rows/1`.

## Running tests — DB requirement

Even tests declared `use ExUnit.Case, async: true` (pure function tests) still require the Docker test DB at port 6544. The full application — including Ecto/Repo — starts when the test suite runs. Always have the test DB running.

## Constraints

- Do NOT use `String.to_atom/1` in test setup or assertions
- Do NOT call `Application.get_env/2` in tests — use the mock injection pattern

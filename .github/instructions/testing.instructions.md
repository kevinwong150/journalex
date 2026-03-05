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

Four Mox mocks are defined in `test/test_helper.exs`:
- `Journalex.MockActivity` for `Journalex.ActivityBehaviour`
- `Journalex.MockTrades` for `Journalex.TradesBehaviour`
- `Journalex.MockSettings` for `Journalex.SettingsBehaviour`
- `Journalex.MockParser` for `Journalex.ParserBehaviour`

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

## CSV fixtures

Use only helpers from `test/support/fixtures.ex`. Do NOT read arbitrary file paths directly.

## File placement

Test files go under `test/journalex/` mirroring the path in `lib/journalex/`.

## Constraints

- Do NOT use `String.to_atom/1` in test setup or assertions
- Do NOT call `Application.get_env/2` in tests — use the mock injection pattern

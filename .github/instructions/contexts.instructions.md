---
applyTo: "lib/journalex/**"
---

# Context module conventions — Journalex

## Behaviour-backed contexts

Each context has a matching `*Behaviour` module for Mox testability. **Not all** public functions have `@callback` entries yet — only those needed by tests that require isolation.

| Context | Behaviour file |
|---|---|
| `Journalex.Trades` | `lib/journalex/behaviours/trades_behaviour.ex` |
| `Journalex.Activity` | `lib/journalex/behaviours/activity_behaviour.ex` |
| `Journalex.Settings` | `lib/journalex/behaviours/settings_behaviour.ex` |
| `Journalex.ActivityStatementParser` | `lib/journalex/behaviours/parser_behaviour.ex` |

When adding a public function that will be called from LiveViews and needs test isolation:
1. Add `@callback` with precise typespec in the behaviour file
2. Implement in the context module
3. Verify the context module has `@behaviour Journalex.<Context>Behaviour`

## Return value conventions

Return values vary by function type:

```elixir
# Mutation functions → tagged tuples
{:ok, value}       # success
{:error, reason}   # failure

# Query functions → bare values (existing pattern)
list_all_trades()                    # returns [%Trade{}, ...]
dedupe_by_datetime_symbol(rows)      # returns [map(), ...]
```

Mutation functions (insert, update, delete) return `{:ok, ...}` / `{:error, ...}`. Query/list functions often return bare lists. Follow whichever pattern the surrounding context functions use.

## Settings vs Application config

**User-configurable settings** (stored in DB, changeable at runtime): use `Journalex.Settings`

```elixir
Settings.get("my_key", "default")            # DB key-value store
Settings.get_default_metadata_version()       # typed helper
Settings.get_r_size()                         # typed helper
```

**Infrastructure config** (API tokens, data source IDs, set via env vars): `Application.get_env` is fine

```elixir
# ✅ OK for infrastructure config read from config/runtime.exs
Application.get_env(:journalex, Journalex.Notion, [])  # used in Notion, DataSources, Client
```

The rule: don't use `Application.get_env` for settings that should be user-configurable at runtime.

## Notion datasource routing

Never hardcode Notion datasource IDs. Use `Journalex.Notion.DataSources` for all version routing.

`DataSources` supports versions 1, 2, and 3 via config keys `:trades_v1_data_source_id`, `:trades_v2_data_source_id`, `:trades_v3_data_source_id`. Only V1 and V2 have `Metadata` schemas today; V3 is config-ready but schema not yet created.

## Removed Notion helpers

`get_rich_text/2` and `maybe_put_rich_text/3` have been removed from `Journalex.Notion`. Do not reference them. Use `get_multi_select_text/2` for comment-style multi-select fields, `get_select/2` for single selects, and `get_checkbox/2` for booleans.

## Atom ↔ string key discipline

- Ecto JSONB returns **string keys**: `%{"done?" => true}`
- Notion extractors return **atom keys**: `%{done?: true}`
- Convert before merging: `Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)`
- Never call `String.to_atom/1` or `String.to_existing_atom/1` on external input

## Metadata entry points

- `Trades.cast_polymorphic_metadata/2` — version-changing writes (routes to V1 or V2 embedded schema)
- `Trades.update_metadata/2` — partial field updates that preserve the existing version

## Cascade delete pattern (shallow / deep modes)

When a context function must optionally clean up associated records, use a `mode: :shallow | :deep` option:

```elixir
def delete_draft(%Draft{} = draft, opts \\ []) do
  case Keyword.get(opts, :mode, :shallow) do
    :shallow -> Repo.delete(draft)
    :deep    -> deep_delete_draft(draft)
  end
end
```

Deep delete rules:
- Wrap the entire operation in `Repo.transaction/1`; call `Repo.rollback/1` on failure
- Capture sub-record IDs **before** deleting the parent
- After deleting the parent(s), count remaining references from other parents — only delete the sub-record if the count is 0 (preserves shared/preset sub-records)
- Return different shapes per mode: `{:ok, count}` (shallow) vs `{:ok, %{combined_count: N, metadata_count: N, writeup_count: N}}` (deep)
- The `@callback` typespec must union both possible success shapes

Bulk variant (`delete_drafts/2`) collects all sub-IDs with one query before deleting, then iterates checking remaining references.

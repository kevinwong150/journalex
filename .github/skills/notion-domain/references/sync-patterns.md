# Sync Patterns — Notion ↔ Ecto

## Overview

Notion sync in Journalex follows a pipeline: **Fetch → Extract → Convert → Merge → Save**.

All sync logic lives in `lib/journalex/notion.ex`. LiveViews call context-level functions; they never interact with the Notion API directly.

## Reading from Notion (Notion → Trade)

### `sync_metadata_from_notion(trade_id, page_id)`

1. Fetches page via `Client.get_page(page_id)`
2. Detects version via `DataSources.get_version(parent_data_source_id)`
3. Routes to `extract_v1_metadata_from_properties/1` or `extract_v2_metadata_from_properties/1`
4. Returns atom-keyed map: `%{done?: true, rank: "S", ...}`
5. Converts to string keys before Ecto update
6. Calls `Trades.update_metadata/2` to merge into existing record

### `sync_writeup_from_notion(trade_id, page_id)`

1. Fetches top-level blocks via `Client.get_block_children(page_id)`
2. For toggle blocks, fetches child blocks one level deep
3. Converts blocks to internal writeup format
4. Saves directly to `trade.writeup`

## Writing to Notion (Trade → Notion)

### `push_trade_metadata(page_id, trade)`

1. Reads `trade.metadata` (string-keyed map from Ecto)
2. Routes to `build_v1_metadata_properties/1` or `build_v2_metadata_properties/1`
3. Generates Notion property map with correct API shapes
4. Calls `Client.update_page(page_id, %{properties: props})`

### `push_trade_writeup(page_id, writeup)`

1. Converts internal writeup format to Notion blocks via `BlockBuilder.to_notion_blocks/1`
2. `BlockBuilder.rich_text/1` automatically chunks any text > 2000 chars into multiple spans — the Notion API rejects a single span exceeding 2000 characters with a silent 400 error
3. Appends blocks to page via `Client.append_block_children(page_id, blocks)`
4. Returns `{:ok, :no_writeup}` if writeup is empty/nil

## Extraction Helpers (Notion → Elixir)

These extract typed values from Notion's nested property shapes:

| Helper | Notion Shape | Returns |
|--------|-------------|---------|
| `get_checkbox(props, key)` | `%{"checkbox" => bool}` | `true`/`false` or `nil` |
| `get_select(props, key)` | `%{"select" => %{"name" => str}}` | string or `nil` |
| `get_number(props, key)` | `%{"number" => num}` | `Decimal` or `nil` |
| `get_rollup_first_select(props, key)` | `%{"rollup" => %{"array" => [%{"select" => ...}]}}` | string or `nil` |
| `get_multi_select_text(props, key)` | `%{"multi_select" => [%{"name" => str}]}` | comma-separated string or `nil` |

## Build Helpers (Elixir → Notion)

These construct Notion API property shapes from Elixir values:

| Helper | Input | Notion Shape |
|--------|-------|-------------|
| `maybe_put_checkbox(map, key, val)` | boolean | `%{checkbox: bool}` |
| `maybe_put_select(map, key, val)` | non-empty string | `%{select: %{name: str}}` |
| `maybe_put_number(map, key, val)` | number | `%{number: num}` |
| `maybe_put_multi_select(map, key, val)` | comma-separated string | `%{multi_select: [%{name: str}]}` |
| `maybe_put_relation(map, key, val)` | page ID string | `%{relation: [%{id: str}]}` |

All `maybe_put_*` helpers are no-ops when the value is `nil` or empty — they return the map unchanged.

## Version Detection Pattern

```
page_properties → parent.data_source_id → DataSources.get_version(id) → 1 or 2
```

This determines which extract/build function pair to use. The routing is **automatic** — callers pass a page ID, and the system detects the version.

## Bulk Check Pattern — `fetch_pages_for_check/3`

For checking many trades against Notion at once, use the targeted batch-fetch function instead of per-trade GETs:

```elixir
Notion.fetch_pages_for_check(titles, ds_id)
# → {:ok, %{title_string => full_page_map}}
```

- Takes a list of trade title strings and a datasource ID
- Chunks into batches of 25; each batch uses an OR-filter of `rich_text: %{equals: title}` per title
- Returns a map keyed by title string; missing titles simply won't have an entry
- Old shape before this function existed: `{trademark_set, id_map}` — do NOT use that pattern

**Check processing is zero-HTTP after prefetch:**

```elixir
# In handle_async after fetching page_cache:
page = Map.get(socket.assigns.check_page_cache, title)
diff = Notion.diff_trade_vs_page(row, page)
```

Never re-query Notion per-row during `process_next_check` — all HTTP happens upfront in the `start_async` phase.

**Parallelizing multiple independent Notion queries inside `start_async`:**

```elixir
start_async(socket, :notion_prefetch, fn ->
  t1 = Task.async(fn -> Notion.list_all_trademarks_with_ids(ds_id) end)
  t2 = Task.async(fn -> Notion.fetch_pages_for_check(titles, ds_id) end)
  [trademark_result, check_result] = Task.await_many([t1, t2], 60_000)
  {trademark_result, check_result}
end)
```

This is safe because `start_async` runs in a separate process, so `Task.await_many` blocking there does not affect the LiveView channel heartbeat.

## Relation Cache Warmup Pattern — targeted lookups

For insert or push flows that need Notion relation page IDs (for example ticker/date relations), do not require a full "Check Notion" run just to populate caches.

- Collect only the missing relation keys from the trades involved in the pending action
- Use `Notion.fetch_ticker_ids/1` and `Notion.fetch_date_ids/1` inside `start_async/3`
- **`fetch_date_ids` must list all pages — never filter by title.** Market Daily page titles are Notion date-mention rich text, not plain text. A `rich_text: {equals: "2026-04-27"}` filter always returns 0 results. The correct implementation fetches all pages from the datasource and builds the date→ID map from the full result set (~127 pages, ~2.7 s). `fetch_ticker_ids` is unaffected (Ticker Details titles are plain text).
- Merge the returned deltas into the existing caches in `handle_async/3`
- Store enough pending-action state to resume the original insert/push flow after the warmup completes

This keeps the LiveView non-blocking and avoids full data-source scans when only a small set of relation IDs is needed.

## Error Handling

- Sync functions return `{:ok, updated_trade}` or `{:error, reason}`
- The Notion Client wraps HTTP errors into `{:error, %{status: code, body: body}}`
- LiveViews handle errors via `put_flash(socket, :error, message)` — they don't retry automatically
- `Client.request_with_retry/5` (in `notion/client.ex`) retries on 429, 502, 503, 504: max 3 attempts, exponential backoff 500ms × 2^(attempt−1) ± 40% jitter, capped at 8s. Used by `query_database` and `retrieve_page`; mutation functions are unchanged.

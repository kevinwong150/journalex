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
2. Appends blocks to page via `Client.append_block_children(page_id, blocks)`
3. Returns `{:ok, :no_writeup}` if writeup is empty/nil

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

## Error Handling

- Sync functions return `{:ok, updated_trade}` or `{:error, reason}`
- The Notion Client wraps HTTP errors into `{:error, %{status: code, body: body}}`
- LiveViews handle errors via `put_flash(socket, :error, message)` — they don't retry automatically

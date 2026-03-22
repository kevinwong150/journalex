---
name: notion-domain
description: "Notion API integration for Journalex. Use when: notion API, notion sync, metadata fields, V1 V2 properties, notion integration, datasource, property names, sync patterns, notion pitfalls."
---

# Notion Domain Knowledge — Journalex

## When to Use

- Adding or modifying Notion sync functionality
- Working with V1/V2 metadata fields
- Debugging Notion API errors
- Understanding property name mapping between Notion and Ecto
- Deciding whether to use MCP tools or Elixir context functions

## API Conventions

- **API version header**: `Notion-Version: 2025-09-03` (non-public extended API)
- **Query endpoint**: `/v1/data_sources/{id}/query` (not `/v1/databases/{id}/query`)
- **Page parent type**: `"data_source_id"` (not `"database_id"`)
- **HTTP client**: Finch via `Journalex.Notion.Client`

## Metadata Versioning

| Version | Module | Status |
|---------|--------|--------|
| 1 | `Journalex.Trades.Metadata.V1` | Legacy-frozen — NEVER add new fields |
| 2 | `Journalex.Trades.Metadata.V2` | Current — 28+ boolean flags + extended fields |
| 3 | (no schema yet) | Config slot exists in `DataSources` via `:trades_v3_data_source_id` |

Discrimination is via `trade.metadata_version` (integer column).

**Entry points:**
- `Trades.cast_polymorphic_metadata/2` — version-changing writes (routes to V1 or V2 schema)
- `Trades.update_metadata/2` — partial field updates preserving existing version

## Key Discipline

- **Ecto** returns JSONB maps with **string keys**: `%{"done?" => true}`
- **Notion extractors** return **atom keys**: `%{done?: true}`
- Before merging atom-keyed maps into Ecto: `Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)`
- **NEVER** use `String.to_atom/1` or `String.to_existing_atom/1` on external input

## DataSources Routing

`Journalex.Notion.DataSources` maps Notion data source IDs → `metadata_version` integers. Routing is automatic during sync — never hardcode version checks in LiveViews.

Key functions:
- `DataSources.get_version(data_source_id)` → version integer or nil
- `DataSources.get_data_source_id(version)` → data source ID string or nil
- `DataSources.all_sources()` → `[{id, version}, ...]`
- `DataSources.v2_data_source_id()` → V2 ID with fallback

## MCP vs Elixir Context — When to Use What

### Read/Inspect (exploring data, no mutations)

Prefer **Notion MCP tools** for speed — no Elixir code needed:
- `API-query-data-source` — query pages in a data source
- `API-retrieve-a-page` — get a single page's properties
- `API-get-block-children` — read page content blocks

### Write/Mutate (create, update, sync)

**ALWAYS** use `Journalex.Notion.*` context functions — they enforce:
- Atom ↔ string key conversion
- DataSources version routing
- Error handling patterns
- Property name correctness

Key write functions:
- `Notion.sync_metadata_from_notion/2` — pull metadata from Notion → trade
- `Notion.sync_writeup_from_notion/2` — pull writeup blocks from Notion → trade
- `Notion.push_trade_writeup/2` — push writeup blocks to Notion page

## Procedures

### Adding a new V2 metadata field

1. Read [property names reference](./references/property-names.md) to verify the Notion property name
2. Add field to `lib/journalex/trades/metadata/v2.ex` schema + `cast/3` list
3. Add `get_*` call in `extract_v2_metadata_from_properties/1` in `notion.ex`
4. Add `maybe_put_*` call in `build_v2_metadata_properties/1` in `notion.ex`
5. Add input in `v2/1` component in `metadata_form.ex`
6. Review [pitfalls](./references/pitfalls.md) before submitting

### Understanding sync flow

Read [sync patterns reference](./references/sync-patterns.md) for the extract → convert → merge pipeline.

### Debugging Notion API issues

1. Check [pitfalls](./references/pitfalls.md) for common mistakes
2. Use Notion MCP `API-retrieve-a-page` to inspect raw property shapes
3. Compare against expected shapes in [sync patterns](./references/sync-patterns.md)

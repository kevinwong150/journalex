# Common Pitfalls — Notion Integration

These are verified mistakes that have occurred or could easily occur in the Journalex codebase.

## 1. `String.to_atom/1` on Notion API data

**Wrong**: `String.to_atom(property_name)` on data from Notion responses
**Why**: Atom table is not garbage-collected; untrusted input creates a DoS vector
**Fix**: Use string keys throughout, or convert with `Atom.to_string/1` when going atom → string

## 2. Adding fields to Metadata V1

**Wrong**: Adding a new `field` to `lib/journalex/trades/metadata/v1.ex`
**Why**: V1 is legacy-frozen to preserve compatibility with existing Notion data
**Fix**: All new fields go into V2 (`lib/journalex/trades/metadata/v2.ex`)

## 3. Hardcoded Notion datasource IDs

**Wrong**: `"27fd32dc-cc42-8024-8400-000ba1f400e4"` in source code
**Why**: IDs come from config and vary between environments
**Fix**: Use `Journalex.Notion.DataSources.get_data_source_id(version)` or `DataSources.all_sources()`

## 4. Wrong property name casing/spacing

**Wrong**: `"EntryTimeslot"` in V1 extraction, or `"Entry Timeslot"` in V2 extraction
**Why**: V1 uses `"Entry Timeslot"` (with space); V2 uses `"EntryTimeslot"` (CamelCase, no space)
**Fix**: Always verify against `extract_v1/v2_metadata_from_properties` in `notion.ex`

## 5. Mixing atom and string keys in maps

**Wrong**: `Map.merge(ecto_map, notion_map)` where ecto_map has string keys and notion_map has atom keys
**Why**: Results in duplicate keys (`"done?"` and `done?` both present)
**Fix**: Convert atom keys first: `Map.new(notion_map, fn {k, v} -> {Atom.to_string(k), v} end)`

## 6. Port 5432 in connection strings

**Wrong**: `hostname: "localhost", port: 5432`
**Why**: Dev DB is on host port 6543, test DB on 6544
**Fix**: Use the correct port from `config/dev.exs` or `config/test.exs`

## 7. Using Cowboy instead of Bandit

**Wrong**: Referencing `Plug.Cowboy` or `cowboy` in deps
**Why**: Journalex uses Bandit as the HTTP server
**Fix**: Use `Bandit` adapter references

## 8. `Application.get_env` for user settings

**Wrong**: `Application.get_env(:journalex, :default_metadata_version)`
**Why**: User-configurable settings are DB-backed for runtime changes
**Fix**: Use `Journalex.Settings.get_default_metadata_version()` and similar typed helpers

## 9. Referencing removed Notion helpers

**Wrong**: Calling `get_rich_text/2` or `maybe_put_rich_text/3`
**Why**: These functions were removed from `Journalex.Notion`
**Fix**: Use `get_multi_select_text/2` for comment fields, `get_select/2` for single selects

## 10. Writing to rollup properties

**Wrong**: Including `"Sector"` or `"CapSize"` in `build_v1/v2_metadata_properties`
**Why**: These are rollup fields — read-only in Notion
**Fix**: Only read via `get_rollup_first_select/2`; never include in property writes

## 11. Notion 2000-character rich_text limit

**Wrong**: Passing a string longer than 2000 chars directly as a single `rich_text` span in a block
**Why**: The Notion API returns a 400 error and silently drops the block write — the push appears to succeed at the HTTP level in some paths but the page is unchanged
**Fix**: Always route text through `BlockBuilder.rich_text/1`; it automatically chunks into multiple spans of ≤ 2000 chars each. Never bypass `BlockBuilder` when constructing paragraph or toggle blocks.

## 12. Assuming V3 property names follow V2 conventions

**Wrong**: Reusing V2 naming rules or field lists when building `Metadata.V3`
**Why**: The live V3 datasource diverges from V2. It includes names like `"Realized P/L"`, relation fields such as `"TickerLink"` and `"DateLink"`. Phase-0 renames changed `"SizeR"` → `"SizeInR"`, added `"RValue"`, and dropped the `(1)` suffix from `"AlignGlobalTrend?"` and `"AlignSectorTrend?"`. Fields can also be added/removed over time (e.g., `"RandomIntradayTrend?"` added; `"StoplossProgress"` and `"TargetProgress"` removed in May 2026).
**Fix**: Use the current V3 snapshot in `references/property-names.md`; do not derive V3 property names from V2 heuristics

## 13. Introspecting V3 datasource schema via `retrieve-a-database`

**Wrong**: Calling the `retrieve-a-database` endpoint with a datasource ID to inspect V3 property/multi-select option lists
**Why**: (1) The extended API's `/v1/databases/{datasource_id}` returns 404 — you must use the underlying `database_id` found in page parent objects. (2) Even with the correct `database_id`, the response does NOT include a `properties` field with multi-select option lists (non-standard API behavior).
**Fix**: To inspect the live property schema, use `mcp_notionapi_API-query-data-source` with the datasource ID and `page_size: 1` — this returns a sample page whose `properties` keys reveal the current field names. For multi-select options, treat hardcoded form arrays as a baseline only: page payloads show values present on returned pages, not a complete unused-option catalog. When rendering V3 multi_select UI, union the persisted values into the option list so already-synced values remain visible/editable even if local defaults lag behind Notion. For fresh/empty datasources, Notion creates the option entries on the first `update_page` write that includes that value — there is no need to pre-seed options.

## 14. Forgetting to wire new datasource ID in docker-compose.yml

**Wrong**: Adding a new `NOTION_TRADES_V3_DATA_SOURCE_ID` config key in `runtime.exs` without also adding it to `docker-compose.yml`
**Why**: The Docker container reads env vars from `docker-compose.yml`; the container will silently use `nil` and datasource routing will fail
**Fix**: After adding a new `Application.get_env` key for a Notion datasource, always add the matching `KEY: "${KEY}"` line to `docker-compose.yml` (and `docker-compose.test.yml` if needed)

## 15. Truncating V3 timeslot buckets at 16:00 or using colon-formatted labels

**Wrong**: Treating `16:00` as the exclusive upper bound in `bucket_for_datetime/1`, or generating labels like `"16:00-16:30"`
**Why**: The live V3 Notion `EntryTimeslot` and `CloseTimeslot` options continue through `"1630-1700"` and use `HHMM-HHMM` labels with no colon separators
**Fix**: Bucket half-hour slots from `09:30` inclusive to `17:00` exclusive. Examples: `16:05` → `"1600-1630"`, `16:35` → `"1630-1700"`

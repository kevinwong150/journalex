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

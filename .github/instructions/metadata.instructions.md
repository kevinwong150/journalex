---
applyTo: "lib/journalex/trades/metadata/**"
---

# Metadata schema conventions — Journalex

## V1 is legacy-frozen

**Never add new fields to `Journalex.Trades.Metadata.V1`.** It exists only to support legacy Notion data.

All new metadata fields go into **V2 only** (`lib/journalex/trades/metadata/v2.ex`).

## V2 field patterns

```elixir
# Boolean flag (most common)
field :my_new_field?, :boolean, default: false

# String classification
field :my_new_field, :string

# Decimal metric
field :my_new_field, :decimal
```

## Changeset requirements

After adding a field, add it to the `cast/3` list in `changeset/2` in the same file.

## After adding a V2 field — cascade these changes

1. `lib/journalex/trades/metadata/v2.ex` — add field + cast it in `changeset/2`
2. `lib/journalex/trades/trade.ex` — update `cast_polymorphic_metadata/2` if it references an explicit field list
3. `lib/journalex/notion.ex` — add `put_if_present` call in `extract_v2_metadata_from_properties/1` AND add `maybe_put_*` call in `build_v2_metadata_properties/1`
4. `lib/journalex_web/live/components/metadata_form.ex` — add input inside the `v2/1` function component

## V3 schema (current production version)

`Metadata.V3` is fully wired at `lib/journalex/trades/metadata/v3.ex`. It uses a `@boolean_fields` module attribute (list of atom keys) to drive casting. New fields go into V3 only — **never into V1 or V2**.

### Adding or removing a V3 boolean — 5-location checklist

1. `v3.ex` — add/remove field, update `@boolean_fields`, update `cast/3`
2. `notion.ex` — `extract_v3_metadata_from_properties/1`
3. `notion.ex` — `build_v3_metadata_properties/1`
4. `metadata_form.ex` — `v3_flag_groups/0` defp function (single source of truth for V3 flag UI groups)
5. `trades_dump_live.ex` — `build_v3_metadata_attrs/1` **and** `metadata_params_builder.ex` — `build_v3/1`

### Removing a Notion field (sync removal only)

When a field is dropped from the live Notion datasource, **keep it in the Ecto embedded schema** — JSONB is non-destructive and historical records retain their data. Only remove it from `extract_v3_metadata_from_properties/1`, `build_v3_metadata_properties/1`, and `v3_flag_groups/0`.

## Notion property names

**Both V1 and V2 use CamelCase (no spaces) for almost all properties.**

Key difference — timeslot properties:
- V1: `"Entry Timeslot"` (has a space — exception to CamelCase rule)
- V2: `"EntryTimeslot"` (no space) + `"CloseTimeslot"` (V2-only)

V1-only properties: `"FollowSetup?"`, `"FollowStopLossManagement?"`, `"UnnecessaryTrade?"`

V2-only properties: `"EntryTimeslot"`, `"CloseTimeslot"`, `"InitialRiskRewardRatio"`, `"BestRiskRewardRatio"`, `"Size"`, `"OrderType"` plus all extended boolean flags (e.g. `"AddSize?"`, `"AlignWithTrend?"`, `"ChoppyChart?"`, etc.)

Shared properties (same name in both): `"Done?"`, `"LostData?"`, `"Rank"`, `"Setup"`, `"CloseTrigger"`, `"RevengeTrade?"`, `"FOMO?"`, `"OperationMistake?"`, `"CloseTimeComment"`

Always verify the exact property name against `extract_v2_metadata_from_properties/1` and `build_v2_metadata_properties/1` in `lib/journalex/notion.ex` before adding a new field.

## Atom ↔ string key rule

Notion extractors return atom-keyed maps. Before merging into an Ecto changeset, convert:

```elixir
Map.new(atom_map, fn {k, v} -> {Atom.to_string(k), v} end)
```

Never use `String.to_atom/1` or `String.to_existing_atom/1`.

---
applyTo: "lib/journalex/trades/metadata/**"
---

# Metadata version migration conventions — Journalex

## Version policy

- V1 is legacy-frozen.
- V2 is legacy-supported for old records and maintenance work.
- V3 is the latest and current production version.
- New metadata fields go into V3 unless you are explicitly fixing legacy V1/V2 compatibility.

## Latest-version migration mindset

When migrating behavior from an older metadata version to the latest version, keep these four layers aligned:

1. Schema and casting
2. Form rendering and form submission
3. Notion extract, build, and diff logic
4. Bulk repair and update flows for existing rows

A V3 migration is incomplete until all four layers agree on field names, storage location, and fallback semantics.

## Legacy versions

### V1 is legacy-frozen

**Never add new fields to `Journalex.Trades.Metadata.V1`.** It exists only to support legacy Notion data.

### V2 is maintenance-only

Use V2 changes only for legacy compatibility or data-maintenance work. Do not put new product behavior into V2 when the task is really about the latest version.

Common V2 field patterns:

```elixir
# Boolean flag (most common)
field :my_new_field?, :boolean, default: false

# String classification
field :my_new_field, :string

# Decimal metric
field :my_new_field, :decimal
```

After adding a V2 field, also add it to the `cast/3` list in `changeset/2` in the same file.

#### After adding a V2 field — legacy maintenance checklist

1. `lib/journalex/trades/metadata/v2.ex` — add field + cast it in `changeset/2`
2. `lib/journalex/trades/trade.ex` — update `cast_polymorphic_metadata/2` if it references an explicit field list
3. `lib/journalex/notion.ex` — add `put_if_present` call in `extract_v2_metadata_from_properties/1` AND add `maybe_put_*` call in `build_v2_metadata_properties/1`
4. `lib/journalex_web/live/components/metadata_form.ex` — add input inside the `v2/1` function component

## V3 schema (current production version)

`Metadata.V3` is fully wired at `lib/journalex/trades/metadata/v3.ex`. It uses a `@boolean_fields` module attribute (list of atom keys) to drive casting.

### Adding or removing a Notion-synced V3 field — 6-location checklist

1. `v3.ex` — add/remove field, update `@boolean_fields` or any value lists, update `cast/3`
2. `notion.ex` — `extract_v3_metadata_from_properties/1`
3. `notion.ex` — `build_v3_metadata_properties/1`
4. `notion.ex` — `metadata_diff_fields(3)` so Check Notion includes the field
5. `metadata_form.ex` — `v3_flag_groups/0` or the relevant V3 form section
6. `trades_dump_live.ex` — `build_v3_metadata_attrs/1` AND `metadata_params_builder.ex` — `build_v3/1`

If the field is computed, display-only, or has fallback semantics, also update the migration rules in the next section.

### Adding an app-only V3 field (NOT synced to Notion) — 4 locations only

1. `v3.ex` — field, `@boolean_fields` or other cast/value lists, `cast/3`
2. `metadata_form.ex` — V3 UI (`v3_flag_groups/0` or relevant section)
3. `trades_dump_live.ex` — `build_v3_metadata_attrs/1`
4. `metadata_params_builder.ex` — `build_v3/1`

Deliberately omit `extract_v3_metadata_from_properties/1`, `build_v3_metadata_properties/1`, and `metadata_diff_fields(3)`. Example: `auto_calculate_from_winning_trade?`.

### Removing a Notion field (sync removal only)

When a field is dropped from the live Notion datasource, **keep it in the Ecto embedded schema**. JSONB is non-destructive and historical records retain their data. Only remove it from `extract_v3_metadata_from_properties/1`, `build_v3_metadata_properties/1`, `metadata_diff_fields(3)`, and the V3 UI.

## High-risk V3 migration rules

These were the actual failure points during the V3 rollout.

### 1. `metadata_diff_fields(3)` is required

If V3 does not have its own `metadata_diff_fields(3)` clause, Check Notion silently falls through to the V2 catch-all and hides V3-specific drift.

### 2. Computed values in JSONB-sourced attrs must use string keys

When inserting computed values into `metadata_attrs` before passing them into Ecto, use string keys:

```elixir
Map.put(attrs, "size_in_r", value)
```

Do **not** use atom keys on JSONB-sourced maps. Ecto `convert_params/1` only converts atom keys when the first key is an atom. On real JSONB maps the first key is typically a string, so atom-keyed computed values are silently dropped.

### 2b. `cast/3` field lists must stay atom-keyed

`cast/3` expects schema field names as atoms. For `Metadata.V3`, keep `@boolean_fields` as a list of atom keys (for example `:done?`), not strings (for example `"done?"`). Converting that list to strings causes runtime `ArgumentError` failures in bound draft/update paths.

### 3. Disabled inputs do not submit

Browsers omit disabled inputs from form payloads. If a V3 field is display-only but still must be saved, render a hidden input alongside the disabled display input:

```html
<input type="hidden" name="r_value" value={@value} />
<input type="number" value={@value} disabled />
```

### 4. `size_in_r` and `r_value` are a paired V3 migration

For V3, these fields are not just renamed properties. They also have fallback semantics for older rows.

- `size_in_r` maps to `"SizeInR"`
- `r_value` maps to `"RValue"`
- `r_value` is the 1R dollar amount and semantically equals `Settings.get_r_size()`
- For V3 LOSE trades, missing `size_in_r` falls back to `auto_compute_size(row)`
- Missing `r_value` falls back to `Settings.get_r_size()`

This means raw DB `nil` is not always the true effective value.

### 5. Push, diff, and bulk repair must share the same effective value rules

If `build_metadata_properties` can synthesize a V3 value during push, then:

1. `diff_trade_vs_page` must compare against that same effective value
2. bulk update must persist the missing computed/fallback value back into DB before pushing
3. `update_all_selected` must not rely only on stale `row_inconsistencies` for selected V3 rows that already have page IDs but are still missing effective `size_in_r` or `r_value`

Otherwise you get a false `nil` vs `nil` “in sync” result and the repair path never runs.

### 6. V3 `close_timeslot` is not the same as V2 `close_timeslot`

- V2 `close_timeslot` is computed from `action_chain`
- V3 `close_timeslot` is stored directly in metadata and must be diffed via `metadata_diff_fields(3)`

Do not copy V2 close-timeslot assumptions into V3 code.

### 7. App-owned V3 data is not metadata

`progression_chain` lives in `journal_data`, not `metadata`. It may be mirrored to Notion `"ProgressionChain"` as a backup, but DB ownership remains `journal_data`.

## Notion property names

Property naming differs by version.

Key timeslot differences:
- V1: `"Entry Timeslot"` (space)
- V2: `"EntryTimeslot"` and `"CloseTimeslot"`
- V3: `"EntryTimeslot"` and `"CloseTimeslot"`, but V3 `close_timeslot` is stored in metadata rather than computed from `action_chain`

V1-only properties: `"FollowSetup?"`, `"FollowStopLossManagement?"`, `"UnnecessaryTrade?"`

V2-only properties: `"EntryTimeslot"`, `"CloseTimeslot"`, `"InitialRiskRewardRatio"`, `"BestRiskRewardRatio"`, `"Size"`, `"OrderType"` plus all extended boolean flags

Shared properties in older versions: `"Done?"`, `"LostData?"`, `"Rank"`, `"Setup"`, `"CloseTrigger"`, `"RevengeTrade?"`, `"FOMO?"`, `"OperationMistake?"`, `"CloseTimeComment"`

### V3 Notion property names (current production)

| Elixir field | Notion property | Notes |
|---|---|---|
| `done?` | `"Done?"` | |
| `lost_data?` | `"LostData?"` | |
| `rank` | `"Rank"` | 5 options only — no `"BAD Trade"` |
| `setup` | `"Setup"` | 7 options |
| `close_trigger` | `"CloseTrigger"` | |
| `order_type` | `"OrderType"` | |
| `entry_timeslot` | `"EntryTimeslot"` | |
| `close_timeslot` | `"CloseTimeslot"` | Stored in metadata for V3; NOT computed from action_chain |
| `initial_risk_reward_ratio` | `"InitialRiskRewardRatio"` | |
| `best_risk_reward_ratio` | `"BestRiskRewardRatio"` | |
| `size_in_r` | `"SizeInR"` | Renamed from V2 `"Size"`; missing V3 LOSE values may be synthesized from `auto_compute_size(row)` |
| `r_value` | `"RValue"` | Renamed from V2 `"SizeNumber"`; semantic value is `Settings.get_r_size()` |
| `choppy_chart?` | `"ChoppyChart?"` | V2 had typo `choppychart?` / `"ChoppyChart?"` |
| `decision_affected_by_other_trade?` | `"DecisionAffectedByOtherTrade?"` | Renamed from V2 `affected_by_other_trade?` |
| `slippage_entry?` | `"SlippageEntry?"` | Renamed from V2 `slipped_position?` |
| `align_ticker_big_picture_trend?` | `"AlignTickerBigPictureTrend?"` | New V3 |
| `align_ticker_intraday_trend?` | `"AlignTickerIntradayTrend?"` | New V3 |
| `adjusted_stoploss?` | `"AdjustedStoploss?"` | New V3 |
| `adjusted_target?` | `"AdjustedTarget?"` | New V3 |
| `align_global_trend?` | `"AlignGlobalTrend?"` | New V3 |
| `align_sector_trend?` | `"AlignSectorTrend?"` | New V3 |
| `averaging_down?` | `"AveragingDown?"` | New V3 |
| `averaging_up?` | `"AveragingUp?"` | New V3 |
| `following_trade?` | `"FollowingTrade?"` | New V3 |
| `following_rule?` | `"FollowingRule?"` | New V3 |
| `lack_confidence?` | `"LackConfidence?"` | New V3 |
| `large_size_in_purpose?` | `"LargeSizeInPurpose?"` | New V3 |
| `small_size_in_purpose?` | `"SmallSizeInPurpose?"` | New V3 |
| `reasonable_entry_story?` | `"ReasonableEntryStory?"` | New V3 |
| `reasonable_exit_story?` | `"ReasonableExitStory?"` | New V3 |
| `scalp?` | `"Scalp?"` | New V3 |
| `should_record_obsidian?` | `"ShouldRecordObsidian?"` | New V3 |
| `size_matching_story?` | `"SizeMatchingStory?"` | New V3 |
| `too_loose_stop_loss?` | `"TooLooseStopLoss?"` | New V3 |
| `use_draft_order?` | `"UseDraftOrder?"` | New V3 |
| `random_intraday_trend?` | `"RandomIntradayTrend?"` | New V3 (May 2026) |
| `close_time_comment` | `"CloseTimeComment"` | multi_select |
| `extra_setup_comment` | `"ExtraSetupComment"` | multi_select; new V3 |
| `good_things` | `"GoodThings"` | multi_select; new V3 |
| `patterns` | `"Patterns"` | multi_select; new V3 |
| `regular_lessons` | `"RegularLessons"` | multi_select; new V3 |
| `sector` | rollup — never written | |
| `cap_size` | rollup — never written | |
| `auto_calculate_from_winning_trade?` | app-only — never synced | |

Always verify the exact property name against `extract_v3_metadata_from_properties/1` and `build_v3_metadata_properties/1` in `lib/journalex/notion.ex` before adding a new field.

## Atom-to-string key rule

Notion extractors return atom-keyed maps. Before merging them into Ecto or JSONB-backed attrs, convert them:

```elixir
Map.new(atom_map, fn {k, v} -> {Atom.to_string(k), v} end)
```

Never use `String.to_atom/1` or `String.to_existing_atom/1`.

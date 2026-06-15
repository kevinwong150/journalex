# Notion Property Names — V1 vs V2 vs V3

Both V1 and V2 use **CamelCase** property names with no spaces, except for one V1 exception.

## Shared Properties (same name in both V1 and V2)

| Property Name | Type | Notes |
|---------------|------|-------|
| `"Done?"` | checkbox | |
| `"LostData?"` | checkbox | |
| `"Rank"` | select | |
| `"Setup"` | select | |
| `"CloseTrigger"` | select | |
| `"Sector"` | rollup | **Read-only** — cannot be written back to Notion |
| `"CapSize"` | rollup | **Read-only** — cannot be written back to Notion |
| `"RevengeTrade?"` | checkbox | |
| `"FOMO?"` | checkbox | |
| `"OperationMistake?"` | checkbox | |
| `"CloseTimeComment"` | multi_select | Stored as comma-separated string in metadata |

## V1-Only Properties (legacy-frozen)

| Property Name | Type | Notes |
|---------------|------|-------|
| `"Entry Timeslot"` | select | **HAS A SPACE** — only exception to CamelCase rule |
| `"FollowSetup?"` | checkbox | |
| `"FollowStopLossManagement?"` | checkbox | |
| `"UnnecessaryTrade?"` | checkbox | |

## V2-Only Properties

### Classification fields

| Property Name | Type | Notes |
|---------------|------|-------|
| `"EntryTimeslot"` | select | CamelCase, NO space (differs from V1) |
| `"CloseTimeslot"` | select | V2-only |
| `"OrderType"` | select | |
| `"Size"` | select | |

### Numeric fields

| Property Name | Type | Notes |
|---------------|------|-------|
| `"InitialRiskRewardRatio"` | number | Returns `Decimal` in Elixir |
| `"BestRiskRewardRatio"` | number | Returns `Decimal` in Elixir |

### Boolean flags (V2-only checkboxes)

| Property Name |
|---------------|
| `"AddSize?"` |
| `"AdjustedRiskReward?"` |
| `"AlignWithTrend?"` |
| `"BetterRiskRewardRatio?"` |
| `"BigPicture?"` |
| `"EarningReport?"` |
| `"FollowUpTrial?"` |
| `"GoodLesson?"` |
| `"HotSector?"` |
| `"Momentum?"` |
| `"News?"` |
| `"NormalEmotion?"` |
| `"Overnight?"` |
| `"OvernightInPurpose?"` |
| `"SlippedPosition?"` |
| `"ChoppyChart?"` |
| `"CloseTradeRemorse?"` |
| `"NoLuck?"` |
| `"NoRisk?"` |
| `"ClearLiquidityGrab?"` |
| `"EntryAfterLiquidityGrab?"` |
| `"InstantLose?"` |
| `"TooTightStopLoss?"` |
| `"AffectedByOtherTrade?"` |
| `"MidRange?"` |
| `"FullyWrongDirection?"` |

## V3 Datasource Snapshot (May 2026)

`Metadata.V3` is fully wired in code (May 2026). These names come from the live datasource `4b5d32dc-cc42-8393-9fcd-87436e8a0327`, confirmed via MCP API query (`mcp_notionapi_API-query-data-source` with `page_size: 1`).

- Snapshot counts: 70 properties total — 41 checkbox, 8 select, 5 multi_select, 6 number, 2 relation, 2 rollup, 3 formula, 1 date, 1 rich_text, 1 title.
- **May 2026 update**: `"RandomIntradayTrend?"` added; `"StoplossProgress"` and `"TargetProgress"` removed from Notion. Ecto schema retains the removed fields (JSONB is safe for historical data) — only extract/build and UI were updated.
- Unlike V1/V2, V3 is not a strict CamelCase/no-space schema. Exception: `"Realized P/L"`.
- **Phase-0 renames completed**: `"AlignGlobalTrend? (1)"` → `"AlignGlobalTrend?"`, `"AlignSectorTrend? (1)"` → `"AlignSectorTrend?"`, `"SizeR"` → `"SizeInR"`, `"RValue"` added. The snapshot list below reflects post-rename state.
- `"ProgressionChain"` is the V3 rich_text backup property for `trade.journal_data.progression_chain`. The canonical value still lives in `journal_data`; Notion stores an arrow-serialized mirror such as `ENTRY→W25→TARGET`.

### Known V3 property names

| Property Name |
|---------------|
| `"AdjustedStoploss?"` |
| `"AdjustedTarget?"` |
| `"AlignGlobalTrend?"` |
| `"AlignSectorTrend?"` |
| `"AlignTickerBigPictureTrend?"` |
| `"AlignTickerIntradayTrend?"` |
| `"AveragingDown?"` |
| `"AveragingUp?"` |
| `"BestRiskRewardRatio"` |
| `"BetterRiskRewardRatio?"` |
| `"CapSize"` |
| `"ChoppyChart?"` |
| `"CloseTimeComment"` |
| `"CloseTimeslot"` |
| `"CloseTradeRemorse?"` |
| `"CloseTrigger"` |
| `"DateLink"` |
| `"Datetime"` |
| `"DecisionAffectedByOtherTrade?"` |
| `"Done?"` |
| `"Duration"` |
| `"EarningReport?"` |
| `"EntryTimeslot"` |
| `"ExtraSetupComment"` |
| `"FollowingTrade?"` |
| `"FollowUpTrial?"` |
| `"FOMO?"` |
| `"FormattedDuration"` |
| `"FullyWrongDirection?"` |
| `"GoodLesson?"` |
| `"GoodThings"` |
| `"HotSector?"` |
| `"InitialRiskRewardRatio"` |
| `"LackConfidence?"` |
| `"LargeSizeInPurpose?"` |
| `"LongTrade?"` |
| `"LostData?"` |
| `"MidRange?"` |
| `"News?"` |
| `"NormalEmotion?"` |
| `"OperationMistake?"` |
| `"OrderType"` |
| `"Overnight?"` |
| `"OvernightInPurpose?"` |
| `"Patterns"` |
| `"ProgressionChain"` |
| `"Rank"` |
| `"Realized P/L"` |
| `"ReasonableEntryStory?"` |
| `"ReasonableExitStory?"` |
| `"RegularLessons"` |
| `"Result"` |
| `"RevengeTrade?"` |
| `"Scalp?"` |
| `"Sector"` |
| `"Setup"` |
| `"ShouldRecordObsidian?"` |
| `"Side"` |
| `"SizeMatchingStory?"` |
| `"SizeNumber"` |
| `"RValue"` |
| `"SizeInR"` |
| `"RandomIntradayTrend?"` |
| `"SlippageEntry?"` |
| `"SmallSizeInPurpose?"` |
| `"Ticker"` |
| `"TickerLink"` |
| `"TooLooseStopLoss?"` |
| `"TooTightStopLoss?"` |
| `"Trademark"` |
| `"UseDraftOrder?"` |
| `"Win?"` |

### Authoritative V3 option sets (May 2026)

These option lists were user-confirmed against the live V3 Notion datasource. Preserve this order in form defaults where order matters. For multi_select fields, still union any already-synced values into the rendered option list so unknown historical values remain editable.

#### Select fields

- `"Rank"`: `"Not Setup"`, `"Bad Setup"`, `"C Trade"`, `"B Trade"`, `"A Trade"`
- `"Setup"`: `"Bouncy Ball - Big Seller/Buyer"`, `"Breakout - Day High/Low"`, `"Reversal - Capitulation"`, `"Reversal - Day High/Low"`, `"Reversal - Pullback Reversal"`, `"Testing Setup"`, `"Not Setup"`
- `"CloseTrigger"`: `"Automatically - Breakeven"`, `"Automatically - Take Profit"`, `"Automatically - Stop Loss"`, `"Manually - Take Profit"`, `"Manually - Stop Loss"`, `"Manually - Reverse"`
- `"OrderType"`: `"Limit Order"`, `"Stop Order"`, `"Market Order"`
- `"EntryTimeslot"` and `"CloseTimeslot"`: `"0930-1000"`, `"1000-1030"`, `"1030-1100"`, `"1100-1130"`, `"1130-1200"`, `"1200-1230"`, `"1230-1300"`, `"1300-1330"`, `"1330-1400"`, `"1400-1430"`, `"1430-1500"`, `"1500-1530"`, `"1530-1600"`, `"1600-1630"`, `"1630-1700"`

#### Multi-select fields

- `"CloseTimeComment"`: `"Consider stop loss"`, `"Consider lock profit"`, `"Early close"`, `"Correct early close"`, `"Will lose more if not close"`, `"Will win more if not close"`, `"Will hit take profit if not close"`, `"Will hit stop loss if not close"`
- `"ExtraSetupComment"`: `"Straight losing"`, `"Zero risk play"`, `"Liquidity grab"`, `"Just hit target then reverse"`, `"Just hit stoploss then reverse"`
- `"GoodThings"`: `"Nothing Good"`, `"Good spotting setup"`, `"Good following plan"`, `"Good try"`, `"Good execution"`, `"Good adjusting stop loss"`, `"Good cut"`, `"Good small size"`, `"Good big size"`, `"Good add size"`, `"Good second try"`, `"Good learning from Alvin"`, `"Good learning from Jason"`
- `"Patterns"`: `"Key level - Intraday"`, `"Key level - Multiday"`, `"Consolidation range"`, `"Capitulation"`, `"Tight Bouncy Ball"`, `"Overbought/Oversold"`, `"Tight selling/buying"`, `"Spike Volume"`, `"Three Inside Down"`, `"Gravestone doji"`, `"Sharp top round top"`, `"Engulfing candle"`, `"Double top/bottom"`, `"Lead Lag"`, `"N/A"`
- `"RegularLessons"`: `"Mental"`, `"Discipline"`, `"Risk Management"`, `"Sizing"`

## Critical Rules

1. **V1 is frozen** — never add new fields or properties to V1
2. **V3 is the current production version** — new fields go into `Metadata.V3`; `extract_v3_metadata_from_properties` and `build_v3_metadata_properties` in `notion.ex`. When a V3 Notion-synced field is added/removed, update all 6 locations: `v3.ex` (field + cast), `notion.ex` (extract + build + `metadata_diff_fields(3)`), `metadata_form.ex` (V3 UI), `trades_dump_live.ex` + `metadata_params_builder.ex` (`build_v3_metadata_attrs`/`build_v3`)
3. **Always verify** the exact property name in `lib/journalex/notion.ex` before using it
4. **The CamelCase/no-space rule only applies to V1/V2** — V3 has naming exceptions such as `"Realized P/L"`
5. **V3 `CloseTimeslot` is metadata-owned** — unlike V2, do not derive it from `action_chain`; include it in `metadata_diff_fields(3)` and the V3 form/push pipeline

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

`Metadata.V3` does not exist yet in code. These names come from the live datasource schema inspected via MCP and are the current reference for future V3 extraction/build work.

- Snapshot counts: 71 properties total — 40 checkbox, 10 select, 5 multi_select, 6 number, 2 relation, 2 rollup, 3 formula, 1 date, 1 rich_text, 1 title.
- Unlike V1/V2, V3 is not a strict CamelCase/no-space schema. Notable exceptions already present: `"Realized P/L"`, `"AlignGlobalTrend? (1)"`, `"AlignSectorTrend? (1)"`.

### Known V3 property names

| Property Name |
|---------------|
| `"AdjustedStoploss?"` |
| `"AdjustedTarget?"` |
| `"AlignGlobalTrend? (1)"` |
| `"AlignSectorTrend? (1)"` |
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
| `"SizeR"` |
| `"SlippageEntry?"` |
| `"SmallSizeInPurpose?"` |
| `"StoplossProgress"` |
| `"TargetProgress"` |
| `"Ticker"` |
| `"TickerLink"` |
| `"TooLooseStopLoss?"` |
| `"TooTightStopLoss?"` |
| `"Trademark"` |
| `"UseDraftOrder?"` |
| `"Win?"` |

## Critical Rules

1. **V1 is frozen** — never add new fields or properties to V1
2. **Until `Metadata.V3` exists, new code-backed properties go to V2 only** — add to `extract_v2_metadata_from_properties` and `build_v2_metadata_properties`
3. **Always verify** the exact property name in `lib/journalex/notion.ex` before using it
4. **The CamelCase/no-space rule only applies to V1/V2** — V3 already has naming exceptions such as `"Realized P/L"` and duplicate-suffixed names

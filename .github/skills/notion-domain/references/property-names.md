# Notion Property Names — V1 vs V2

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

## Critical Rules

1. **V1 is frozen** — never add new fields or properties to V1
2. **New properties go to V2 only** — add to `extract_v2_metadata_from_properties` and `build_v2_metadata_properties`
3. **Always verify** the exact property name in `lib/journalex/notion.ex` before using it
4. **CamelCase everywhere** except V1's `"Entry Timeslot"` (space)

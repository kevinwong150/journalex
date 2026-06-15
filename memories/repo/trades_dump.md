# Trades Dump Page — Verified Facts

## PreflightChecks module

- Location: `lib/journalex/trades/preflight_checks.ex`
- Pure, stateless module — no DB calls, no side effects
- `@checks` module attribute holds a list of `{check_name, fun_ref}` pairs using `&__MODULE__.fun/2` captures
- 4 checks defined: `win_empty_size` (V2 only), `missing_ticker_relation`, `missing_date_relation`, `cache_not_loaded`
- Each check function receives `(trade, assigns)` and returns a list of issue maps or `[]`
- `run_preflight/3` helper in `TradesDumpLive` calls all checks and collects issues before allowing push/bulk-push/insert operations

## Pre-flight issue map shape

```elixir
%{
  trade_label: "AAPL 2025-04-01",  # human-readable trade identifier; nil for global issues
  check_name: :cache_not_loaded,
  message: "Cache not loaded — ..."
}
```

- `trade_label: nil` means the issue is global (not tied to a single trade), e.g., `cache_not_loaded`
- HEEx templates must guard with `:if={issue.trade_label}` before rendering per-trade labels

## Tuple shapes in TradesDumpLive assigns

- `bulk_push_to_notion` eligible list: `{idx, trade, draft}` tuples — extract trades with `Enum.map(eligible, fn {_idx, trade, _draft} -> trade end)`
- `insert_missing_notion` queue: `{row, idx}` tuples — extract rows with `Enum.map(queue, fn {row, _idx} -> row end)`

## Inline metadata pending state

- `TradesDumpLive` keeps unsaved inline metadata in `:pending_metadata_by_idx`, keyed by rendered row index; populate it from `"metadata_changed"` params and clear the row entry on save/reset/apply-draft/sync, or clear the whole map on global version switch
- `AggregatedTradeList` must overlay `pending_metadata_by_idx[idx]` onto the persisted trade before rendering `MetadataForm`; progression-chain rerenders otherwise reset unsaved metadata selections back to the saved record

## Draft application semantics

- `handle_event("apply_draft", ...)` and `handle_event("bind_combined_draft", ...)` must propagate `metadata_draft.journal_data["progression_chain"]` into `trade.journal_data["progression_chain"]` when the draft actually contains that key
- If the draft does not contain a `"progression_chain"` key, preserve the trade's existing `journal_data`; a missing key means "leave app-owned progression data untouched", not "clear it"

## Auto-compute size_in_r pattern

- `maybe_auto_compute_size_in_r/2` in `trades_dump_live.ex` returns `{updated_attrs, warning_or_nil}` — called from both `apply_draft` and `bind_combined_draft` handlers
- Formula: `size_in_r = round(|realized_pl| / (r_size × initial_risk_reward_ratio), 2)` — runs at bind/apply time, not at form display time
- Triggered only when `auto_calculate_from_winning_trade?` is `true` in the draft metadata
- `decimal_to_float_or_nil/1` helper handles `Decimal`, float, integer, binary string, and `nil` safely for numeric JSONB fields
- **String keys required**: when injecting computed values into the JSONB-sourced attrs map (e.g. `Map.put(attrs, "size_in_r", value)`), always use string keys — atom keys are silently dropped by Ecto's `convert_params/1` when the map's first key is a string (see pitfall #32 in copilot-instructions.md)
- The "Compute Size in R" button lives in `aggregated_trade_list.ex` (injected before `render_metadata_form`) — not inside the metadata form component; keeps MetadataForm props stable and avoids prop-drilling

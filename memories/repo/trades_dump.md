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

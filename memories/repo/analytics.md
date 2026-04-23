# Analytics — Verified Facts

## Locations
- Context: `lib/journalex/analytics.ex`
- Behaviour: `lib/journalex/behaviours/analytics_behaviour.ex` (NOT at root level)
- LiveViews: `lib/journalex_web/live/analytics/`
- Period helpers: `lib/journalex_web/live/analytics/period_helpers.ex`
- Components: `lib/journalex_web/live/components/` — `chart_component.ex`, `analytics_filter_bar.ex`, `kpi_card.ex`, `info_tooltip.ex`

## Chart Update Architecture (CRITICAL)
- All chart divs have `phx-update="ignore"` → morphdom won't patch them
- `updated()` callback NEVER fires on ignored divs
- Chart data delivered via: server `push_event("chart-update", %{id:, option:})` → JS `handleEvent("chart-update", ...)`
- `push_event` must be the final call in `reload/2` — it returns the socket
- `notMerge: true` used in `handleEvent` (full option replacement on reload)

## Calendar Heatmap (B2)
- Uses category grid (NOT ECharts `calendar` coordinate system)
- X-axis = ISO week labels, Y-axis = ["Mon","Tue","Wed","Thu","Fri"]
- Two series: series 0 = no-trade cells (striped decal), series 1 = trade cells
- `visualMap.seriesIndex: [1]` — colour scale only applies to trades series
- `aria: %{enabled: true}` required for `itemStyle.decal` to render
- No-trade cells only generated for past weekdays up to today (not future)

## Filter Bar Events
- `"set_period"` — period preset; handled by all 3 live LiveViews
- `"toggle_version"` — toggle metadata version filter
- `"filter_dates"` — phx-submit (NOT phx-change) to avoid reload on every keystroke
- `"set_r_mode"` — R / USD / Both toggle
- `"reload"` — manual chart refresh

## Period Helper
- `PeriodHelpers.period_to_dates/1` returns `{from_iso | nil, to_iso | nil}`
- Values: `"this_week"`, `"last_week"`, `"this_month"`, `"last_month"`, `"ytd"`, `"all"`, `"month:YYYY-MM"`, `"week:YYYY-MM-DD"`

## Live Pages (Phase 2 complete)
- `/analytics/dashboard` — KPIs + equity curve, YTD default
- `/analytics/calendar` — Mon–Fri heatmap
- `/analytics/risk` — R:R histogram + scatter, V2-only

## Phase 3 (stub pages, not yet implemented)
- equity, breakdown, tickers, time, behavior, scorecard, streaks, compare
- These stub LiveViews do NOT yet have `handle_event("set_period", ...)` — must add when implementing

## Implemented Analytics Functions
- `kpi_summary/1`, `equity_curve/1`, `calendar_heatmap/2`, `rr_analysis/1`, `available_versions/0`
- 9 functions return stubs with `# TODO`: breakdown_by_dimension, long_vs_short, flags_impact, time_heatmap, day_of_week_breakdown, monthly_breakdown, scorecard_periods, streak_data, ticker_summary

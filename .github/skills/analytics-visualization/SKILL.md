---
name: analytics-visualization
description: "Analytics and data visualization for Journalex trading performance. Use when: analytics, visualization, dashboard, equity curve, calendar heatmap, ECharts, R-multiples, trade performance, behavioral flags, risk reward analysis, breakdown, scorecard, streaks, ticker analysis, period comparison, Journalex.Analytics context, chart component, analytics filter bar, kpi card, /analytics routes, analytics phase, performance analysis, trading analytics."
---

# Analytics Visualization — Journalex

## When to Use

Load this skill whenever you are working on:
- Any file under `lib/journalex_web/live/analytics/`
- `lib/journalex/analytics.ex` or `lib/journalex/analytics_behaviour.ex`
- Any component in `live/components/` prefixed with `chart_`, `analytics_`, or `kpi_`
- Routes starting with `/analytics/`
- The `analytics_r_mode` setting in `Journalex.Settings`
- `Hooks.Chart` in `assets/js/app.js`
- `assets/package.json` (ECharts installation)
- Any query that filters on `trades.metadata` JSONB for aggregation purposes

---

## Locked Decisions

These were established in the planning session (April 2026) and must not be revisited without user confirmation:

| Decision | Choice |
|---|---|
| Chart library | **ECharts (Apache)** — install via npm in `assets/`, wire up via LiveView hook |
| Metadata version handling | **Global version filter (Option A)** — one set of pages for all versions; V2-only sections get a "requires V2+" badge; version list is dynamic (from DB), not hardcoded |
| `done?` filter | **Always applied** — analytics count only `done? = true` trades; this is not user-configurable |
| Exception-day exclusion | **Always applied in the shared analytics query** — no per-page toggle in this pass; dates live in DB-backed Settings as a JSON array string of ISO dates; Settings UI uses repeatable native `type=date` inputs with add/remove controls; validation, normalization, and deduplication happen on save |
| P&L default unit | **R-multiples** (`realized_pl / r_size`); toggle to $ or both; persisted in DB-backed Settings |
| R/$ toggle persistence | **`analytics_r_mode` setting** — DB-backed via `Journalex.Settings`; values: `"r"` | `"usd"` | `"both"`; default `"r"` |
| Dashboard default period | **YTD (year to date)** |
| Analytics nav pin | `/analytics/dashboard` added to `@default_nav_pinned_pages` in `NavHelpers` |
| Priority build order | A1 Dashboard → B2 Calendar Heatmap → F1 Risk/Reward |
| Export | Not needed for now |

---

## Page Catalog

All routes live under `scope "/", JournalexWeb` in `router.ex`. Analytics LiveViews are namespaced under `JournalexWeb.Analytics.*`.

### A — Overview

**A1. Performance Dashboard** — `/analytics/dashboard`
- Module: `JournalexWeb.Analytics.DashboardLive`
- KPI strip: Total R, Win Rate, Trade Count, Avg R, Best trade, Worst trade, Profit Factor, Expectancy
- Period selector: 7d / 30d / 90d / YTD (default) / All Time / Custom
- Mini equity curve (ECharts line), Win/Loss donut (ECharts pie), recent 5 trades table
- Uses: `Analytics.kpi_summary/1`, `Analytics.equity_curve/1`
- ECharts types: `line`, `pie`

### B — Capital Curve

**B1. Equity Curve & Drawdown** — `/analytics/equity`
- Module: `JournalexWeb.Analytics.EquityLive`
- Cumulative R line, granularity toggle (daily/weekly/monthly), daily R bars (green/red), drawdown % line, rolling win rate line
- Stat strip: max drawdown, current drawdown, recovery factor, longest win/loss streaks
- Uses: `Analytics.equity_curve/1`, `Analytics.streak_data/1`
- ECharts types: `line`, `bar`

**B2. Trade Calendar Heatmap** — `/analytics/calendar`
- Module: `JournalexWeb.Analytics.CalendarLive`
- Mon–Fri grid heatmap (weekends hidden): x-axis = ISO weeks, y-axis = Mon–Fri
- Color intensity = R value magnitude (green profit / red loss / white neutral)
- Past weekdays with no trades shown as **diagonal-striped grey cells** (`aria: enabled, itemStyle.decal`)
- Two ECharts series: series 0 = no-trade cells (silent, fixed style); series 1 = trade cells
- `visualMap` must be a **list** `[vm0, vm1]`: vm0 targets series 0 with `show: false` and a single grey color; vm1 targets series 1 with the R gradient. A single map with `seriesIndex: [1]` leaves series 0 cells invisible.
- Uses: `Analytics.calendar_heatmap/2`
- ECharts types: `heatmap` on a category `grid` (NOT the ECharts `calendar` coordinate system)

### C — Attribution

**C1. Breakdown Analysis** — `/analytics/breakdown`
- Module: `JournalexWeb.Analytics.BreakdownLive`
- Tabbed: Rank / Setup / Sector / Close Trigger / Cap Size / Long vs Short
- All tabs share the filter bar state
- Uses: `Analytics.breakdown_by_dimension/2`, `Analytics.long_vs_short/1`
- ECharts types: `bar` (horizontal for Setup/Sector), `bar` grouped

**C2. Ticker Analysis** — `/analytics/tickers`
- Module: `JournalexWeb.Analytics.TickersLive`
- Searchable leaderboard table: trade count, win rate, total R, avg R, last traded
- Click ticker → per-ticker equity curve + mini trade table + win rate gauge
- Top 10 best/worst tickers leaderboard cards
- Uses: `Analytics.ticker_summary/1`
- ECharts types: `line` (per-ticker equity), `gauge`

### D — Time Patterns

**D1. Time Analysis** — `/analytics/time`
- Module: `JournalexWeb.Analytics.TimeLive`
- Entry timeslot × day-of-week heatmap (color = avg R)
- Close timeslot × day-of-week heatmap (V2-only, gated)
- Day-of-week bar chart (R and win/loss count)
- Monthly P&L bars (Jan–Dec)
- Duration scatter: duration (integer) vs realized R, color = WIN/LOSE
- **Duration Band Performance chart** — full-width dual-axis bar+line; 7 hold-duration bins (0–15m through 180m+); bars = Total R (green/red), line = Win Rate % (right axis, 0–100); no V2 gate (duration column on all versions)
- Uses: `Analytics.time_heatmap/2`, `Analytics.timeslot_breakdown/2`, `Analytics.day_of_week_breakdown/1`, `Analytics.monthly_breakdown/1`, `Analytics.duration_band_breakdown/1`
- ECharts types: `heatmap`, `bar` (bar+line combo for timeslot charts), `scatter`, `bar+line` (dual-axis for duration bands)

### E — Psychology

**E1. Behavioral Flags** — `/analytics/behavior`
- Module: `JournalexWeb.Analytics.BehaviorLive`
- Flag frequency table: count + % of trades for each flag
- P&L impact table: avg R when flag ON vs avg R when flag OFF — dollar/R cost per behavior
- Negative flag total cost card
- Flag trend chart per month (improvement tracker)
- Flag co-occurrence heatmap (which flags appear together)
- V2-only for extended flags; V1 flags shown separately or with badge
- Uses: `Analytics.flags_impact/1`
- ECharts types: `heatmap`, `bar`, `line`

### F — Risk

**F1. Risk / Reward** — `/analytics/risk`
- Module: `JournalexWeb.Analytics.RiskLive`
- R-multiple histogram (realized_pl / r_size)
- Initial R:R vs actual result scatter (x = initial_risk_reward_ratio, y = realized R, color = WIN/LOSE)
- Best R:R over time line chart
- Expectancy display: `(Win% × Avg Win R) − (Loss% × Avg Loss R)`
- R:R fulfillment rate: % of trades that met initial R:R target
- **V2-only** — V1 trades have no R:R data; show "requires V2" badge, exclude V1 silently
- Uses: `Analytics.rr_analysis/1`
- ECharts types: `bar` (histogram), `scatter`, `line`

### G — Progress Tracking

**G1. Periodic Scorecard** — `/analytics/scorecard`
- Module: `JournalexWeb.Analytics.ScorecardLive`
- Week/month table: Trade Count, Win%, Total R, Avg R, Top Rank, most frequent flag
- Sparklines in R column, trend arrows (improving/declining), best/worst period highlight
- Uses: `Analytics.scorecard_periods/2`
- ECharts types: `line` (sparklines via small inline charts)

**G2. Streak & Consistency** — `/analytics/streaks`
- Module: `JournalexWeb.Analytics.StreaksLive`
- Current streak indicator, full streak history bar (green/red per trade), longest streaks all-time
- Profitable days % and profitable weeks % counters
- Uses: `Analytics.streak_data/1`
- ECharts types: `bar`

### H — Comparison

**H1. Period Comparison** — `/analytics/compare`
- Module: `JournalexWeb.Analytics.CompareLive`
- Two custom date pickers (Period A vs Period B)
- KPIs side-by-side, equity curves overlaid on same chart
- Rank distribution grouped bar, flag frequency grouped bar
- Uses: `Analytics.kpi_summary/1`, `Analytics.equity_curve/1`, `Analytics.breakdown_by_dimension/2`, `Analytics.flags_impact/1` (called twice with different date opts)
- ECharts types: `line`, `bar` grouped

---

## Architecture

### ECharts Installation

```
assets/
  package.json          ← add: { "dependencies": { "echarts": "^5.x" } }
  js/
    app.js              ← add Hooks.Chart
```

In `mix.exs`, configure esbuild to use `node_modules`:
```elixir
esbuild: [
  args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets
           --external:/fonts/* --external:/images/* --loader:.svg=file
           --node-paths=node_modules),   # ← add this
  ...
]
```

Run `npm install --prefix assets` to install ECharts.

### Hooks.Chart Pattern (app.js)

**CRITICAL:** All chart divs use `phx-update="ignore"` to prevent morphdom from corrupting ECharts-injected SVG children. Because `phx-update="ignore"` also blocks `data-option` attribute updates and the `updated()` callback, chart data is delivered via **`push_event("chart-update", %{id: chart_id, option: map})`** from the server. The JS hook receives it via `handleEvent`.

```javascript
Hooks.Chart = {
  mounted() {
    const option = JSON.parse(this.el.dataset.option);
    this.chart = echarts.init(this.el, null, { renderer: "canvas" });
    this.chart.setOption(option);
    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
    // phx-update="ignore" blocks DOM patches, so updates come via push_event
    this.handleEvent("chart-update", ({id, option}) => {
      if (id === this.el.id) {
        this.chart.setOption(option, { notMerge: true });
        this.chart.resize();
      }
    });
  },
  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    this.chart.dispose();
  }
}
```

**Server side** — in LiveView `reload/2`:
```elixir
defp reload(socket, changes) do
  socket = assign(socket, changes)
  # ... compute new option ...
  push_event(socket, "chart-update", %{id: "chart-id", option: option})
end
```

Template side:
```heex
<div
  id={"chart-id"}
  phx-hook="Chart"
  phx-update="ignore"
  data-option={Jason.encode!(@option)}
  class="w-full h-64"
/>
```

**Important:** The ECharts option map is built server-side in Elixir and JSON-encoded into `data-option`. Never build chart options in JavaScript.

### Analytics Context

**Files:**
- `lib/journalex/analytics.ex` — context module
- `lib/journalex/analytics_behaviour.ex` — behaviour for Mox
- Mock in `test/test_helper.exs`: `Mox.defmock(Journalex.MockAnalytics, for: Journalex.AnalyticsBehaviour)`

**Standard `opts` accepted by all functions:**
```elixir
# versions: list of integers — default: all distinct metadata_version values in DB
# from: Date — default: nil (no lower bound)
# to: Date — default: nil (no upper bound)
# r_size: float — default: Settings.get_r_size()
# done? filter is ALWAYS applied; it is not an opt
```

**Planned functions:**
```elixir
kpi_summary(opts)          # → %{total_r, win_rate, trade_count, avg_r, best_r, worst_r, profit_factor, expectancy}
equity_curve(opts)         # → [{date, cumulative_r}]
calendar_heatmap(year, opts) # → [{"YYYY-MM-DD", r_value}]
breakdown_by_dimension(dimension, opts)  # dimension: :rank | :setup | :sector | :close_trigger | :cap_size | :order_type
                           # → [{label, total_r, win_rate, count}]
long_vs_short(opts)        # → %{long: kpis, short: kpis}
flags_impact(opts)         # → [{flag_name, avg_r_on, avg_r_off, count_on, count_off}]
rr_analysis(opts)          # → %{histogram_bins, scatter_data, expectancy, fulfillment_rate}
time_heatmap(dimension, opts) # dimension: :entry_timeslot | :close_timeslot → [{timeslot, weekday, avg_r}]
timeslot_breakdown(dimension, opts) # dimension: :entry_timeslot | :close_timeslot → [{ts, total_r, avg_r, wins, losses}] sorted by ts
day_of_week_breakdown(opts)   # → [{weekday, total_r, wins, losses}]
monthly_breakdown(opts)    # → [{month_label, total_r, wins, losses}]
scorecard_periods(unit, opts) # unit: :week | :month → [{period_label, count, win_pct, total_r, avg_r, top_rank, top_flag}]
streak_data(opts)          # → %{current_streak, max_win_streak, max_loss_streak, per_trade_sequence}
ticker_summary(opts)       # → [{ticker, count, win_rate, total_r, avg_r, last_date}]
```

### JSONB Query Patterns

All analytics queries filter `done? = true` unconditionally. Because the key `"done?"` contains `?`, it must be passed as a **bound parameter**, not embedded in the fragment string (Ecto counts every `?` in the string as a placeholder):
```elixir
# CORRECT — key passed as second bound arg
where: fragment("(?->>?)::boolean = true", t.metadata, "done?")

# WRONG — the ? in done? is counted as a placeholder, causing arg mismatch
# where: fragment("(?->>'done?')::boolean = true", t.metadata)
```

Extract a metadata field:
```elixir
select: fragment("?->>'rank'", t.metadata)
```

Filter by metadata version (use `t.metadata_version` column, not JSONB — it is a native column):
```elixir
where: t.metadata_version in ^versions
```

**GIN index:** Check `priv/repo/migrations/` for an existing index on `trades.metadata`. If absent, create one before Phase 2 work. Migration pattern:
```elixir
create index(:trades, [:metadata], using: :gin)
```

### R-Multiples

- Helper in `Analytics` (or a shared module): `to_r(decimal, r_size)` → `Decimal.to_float(decimal) / r_size |> Float.round(2)`
- `r_size` read from `Settings.get_r_size()` (default 8.0)
- `analytics_r_mode` setting controls display unit — add to `Journalex.Settings`:
  ```elixir
  @analytics_r_mode_key "analytics_r_mode"
  def get_analytics_r_mode, do: get(@analytics_r_mode_key) || "r"
  def set_analytics_r_mode(mode) when mode in ["r", "usd", "both"], do: put(@analytics_r_mode_key, mode)
  ```
- The Analytics context functions always return raw R values; the LiveView reads `r_mode` from Settings and formats for display

### Version Filter Design

- Do NOT hardcode `[1, 2]` — query distinct `metadata_version` values from DB at mount time
- Example: `from(t in Trade, select: t.metadata_version, distinct: true) |> Repo.all()`
- Populate the `AnalyticsFilterBar` version checkboxes dynamically
- Scales to V3, V4 automatically

### Shared Components

**`ChartComponent`** (`lib/journalex_web/live/components/chart_component.ex`)
- Pure function component
- attrs: `id` (string, required), `option` (map, required), `class` (string, default "w-full h-64")
- Renders: `<div phx-hook="Chart" phx-update="ignore" data-option={Jason.encode!(@option)} ...>`
- `phx-update="ignore"` is required to prevent morphdom from corrupting ECharts SVG children
- Jason.encode! called here so callers pass a raw map

**`AnalyticsFilterBar`** (`lib/journalex_web/live/components/analytics_filter_bar.ex`)
- attrs: `versions_available` (list of integers), `selected_versions` (list of integers), `from` (string | nil), `to` (string | nil), `r_mode` (string)
- Two-row layout:
  - Row 1 (presets): 6 quick-select pills (This Week, Last Week, This Month, Last Month, YTD, All Time) + Month picker (last 18 months) + Week picker (last 26 ISO weeks) — all fire `"set_period"`
  - Row 2 (detail): Version toggle buttons + From/To date inputs (`phx-submit="filter_dates"`, Apply button) + R/$/Both toggle + `↺ Reload` button
- Sends events: `"set_period"`, `"toggle_version"`, `"filter_dates"`, `"set_r_mode"`, `"reload"`
- Period values: `"this_week"`, `"last_week"`, `"this_month"`, `"last_month"`, `"ytd"`, `"all"`, `"month:YYYY-MM"`, `"week:YYYY-MM-DD"`
- Shared across all analytics LiveViews

**`PeriodHelpers`** (`lib/journalex_web/live/analytics/period_helpers.ex`)
- `period_to_dates/1` — converts period string → `{from_iso | nil, to_iso | nil}`
- All 8 period variants handled; unknown variants raise FunctionClauseError
- Alias in LiveViews: `alias JournalexWeb.Analytics.PeriodHelpers`

**`KpiCard`** (`lib/journalex_web/live/components/kpi_card.ex`)
- attrs: `label` (string), `value` (string), `tooltip` (string | nil), `delta` (string | nil), `delta_direction` (:up | :down | nil), `class` (string)
- Renders a styled card with label, large value, optional ⓘ tooltip icon, and optional delta indicator
- When `tooltip` is set, an `<InfoTooltip>` ⓘ icon renders inline after the label

**`InfoTooltip`** (`lib/journalex_web/live/components/info_tooltip.ex`)
- attrs: `text` (string, required), `class` (string)
- Pure CSS hover tooltip: ⓘ icon, dark box above on hover, Tailwind `group-hover:opacity-100`; no JavaScript
- Import with `import JournalexWeb.InfoTooltip`; use as `<.info_tooltip text="..." />`

### Navigation Update

In `lib/journalex_web/nav_helpers.ex`:
- `@all_pages` has 3 analytics entries: `analytics_dashboard`, `analytics_calendar`, `analytics_risk` (stub pages removed)
- `@default_nav_pinned_pages` includes `"analytics_dashboard"`

In `lib/journalex_web/components/layouts/app.html.heex`:
- Desktop Pages mega-menu is a **2-column grid** (`w-80`, `grid-cols-2`): left = Trades + Drafts; right = Statements + Analytics + Settings
- Analytics section shows only 3 live pages: Dashboard, Trade Calendar, Risk / Reward
- Mobile menu matches the same 3 live pages

### Routes

```elixir
# In router.ex, under scope "/", JournalexWeb do
live "/analytics/dashboard", Analytics.DashboardLive
live "/analytics/equity", Analytics.EquityLive
live "/analytics/calendar", Analytics.CalendarLive
live "/analytics/breakdown", Analytics.BreakdownLive
live "/analytics/tickers", Analytics.TickersLive
live "/analytics/time", Analytics.TimeLive
live "/analytics/behavior", Analytics.BehaviorLive
live "/analytics/risk", Analytics.RiskLive
live "/analytics/scorecard", Analytics.ScorecardLive
live "/analytics/streaks", Analytics.StreaksLive
live "/analytics/compare", Analytics.CompareLive
```

---

## File Structure (analytics additions)

```
lib/journalex/
  analytics.ex                          ← new Analytics context
  behaviours/
    analytics_behaviour.ex              ← new behaviour for Mox (NOT analytics_behaviour.ex at root)

lib/journalex_web/live/analytics/
  period_helpers.ex                     ← new: period_to_dates/1 for all period presets
  dashboard_live.ex
  dashboard_live.html.heex
  equity_live.ex
  equity_live.html.heex
  calendar_live.ex
  calendar_live.html.heex
  breakdown_live.ex
  breakdown_live.html.heex
  tickers_live.ex
  tickers_live.html.heex
  time_live.ex
  time_live.html.heex
  behavior_live.ex
  behavior_live.html.heex
  risk_live.ex
  risk_live.html.heex
  scorecard_live.ex
  scorecard_live.html.heex
  streaks_live.ex
  streaks_live.html.heex
  compare_live.ex
  compare_live.html.heex

lib/journalex_web/live/components/
  chart_component.ex                    ← new: wraps ECharts hook div
  analytics_filter_bar.ex              ← new: version + date + R/$ filter bar
  kpi_card.ex                          ← new: reusable KPI display card

assets/
  package.json                          ← new: npm deps (echarts)
  js/
    app.js                              ← add Hooks.Chart

priv/repo/migrations/
  *_add_gin_index_trades_metadata.exs  ← new if GIN index not already present

test/test_helper.exs                    ← add MockAnalytics defmock
```

---

## Pitfalls to Avoid

1. **Never hardcode the version list** (`[1, 2]`) — query distinct `metadata_version` from DB so V3+ works automatically
2. **`done?` filter is not optional** — every analytics query must use `fragment("(?->>?)::boolean = true", t.metadata, "done?")`. The `?` in `"done?"` is a bind placeholder in Ecto; pass the key as a second argument, never inline it in the string
3. **Never build ECharts options in JavaScript** — build the option map in Elixir and JSON-encode into `data-option`; JS only calls `setOption`
4. **`updated()` is NOT used in Hooks.Chart** — `phx-update="ignore"` prevents it from firing. Chart updates come exclusively via `push_event("chart-update", ...)` + `handleEvent`. Never try to restore `updated()` for chart updates.
5. **V2-only fields (R:R, close_timeslot, extended flags)** — gate with a badge rather than silently returning empty data; the user should know why a chart is blank
6. **`analytics_r_mode` is a Settings value** — read it at LiveView mount and reload it when the toggle fires `"set_r_mode"` event; do not store it only in socket assigns
7. **`metadata_version` is a native column** — filter on `t.metadata_version in ^versions`, not via JSONB fragment
8. **Port discipline** — dev DB is port `6543`, test DB is `6544`; never hardcode `5432`
9. **Jason.encode! in component, not in LiveView** — `ChartComponent` calls `Jason.encode!(@option)`; LiveViews pass raw maps to the component
10. **`AnalyticsFilterBar` events are handled by the parent LiveView**, not the component — use `phx-target` or let events bubble to the LiveView's `handle_event`
11. **Use `import`, not `alias`, for `<.component />` syntax** — `alias JournalexWeb.ChartComponent` does NOT bring `chart/1` into scope; use `import JournalexWeb.ChartComponent` instead
12. **ECharts `decal` patterns require `aria: %{enabled: true}`** in the option map — without it, `itemStyle.decal` silently does nothing
13. **ECharts `decal` / stripe patterns require `renderer: "canvas"`** — SVG renderer silently ignores decals. `echarts.init(el, null, { renderer: "canvas" })` is required for any chart using `itemStyle.decal`. This affects **all charts** in the app (single renderer setting in `app.js`), not just the calendar.
14. **Every heatmap series must have a matching `visualMap` entry** — a heatmap series with no associated visualMap is rendered invisible. When multiple heatmap series share a grid, `visualMap` must be a **list** `[vm0, vm1, ...]` with each entry targeting its series via `seriesIndex`. A single map object with `seriesIndex: [1]` leaves series 0 cells invisible.
15. **Do NOT use ECharts `calendar` coordinate system for weekday-only grids** — it always renders all 7 days. Use a category grid (`xAxis: %{type: "category"}`, `yAxis: %{type: "category"}`) with Mon–Fri as the Y-axis data instead
14. **`filter_dates` form uses `phx-submit`, not `phx-change`** — `phx-change` fires on every keystroke; `phx-submit` only fires on explicit Apply button click
15. **ECharts formatter functions cannot be passed from Elixir** — the option map is JSON-serialised, so JS function values are lost. Use a **sentinel string pattern**: put a sentinel like `tooltipFormatter: "heatmap_date"` in the Elixir option map, then define a `resolveFormatters(option)` function in `app.js` that inspects the option for known sentinels and replaces them with real JS functions before calling `chart.setOption(option)`
16. **HEEx bare `if` in list literals is a syntax error** — `[..., if cond, do: a, else: b]` fails. Use `[..., if(cond, do: a, else: b)]`. Complex conditions: `if(Map.get(m, :k) >= 0, do: ...)` not `if Map.get(m, :k) >= 0, do:`
17. **`<%# comment %>` is deprecated in HEEx** — produces a warning-as-error; use `<%!-- comment --%>` instead
18. **ECharts `{c}` formatter in heatmap shows the entire data array** — for raw array data like `[xi, yi, value]`, `{c}` renders the whole array as a comma-joined string, not just the value. Use `{@[2]}` for simple label templates, or disable cell labels entirely with `label: %{show: false}`. `{b}` renders the series name.
19. **Heatmap `visualMap` colors by the last numeric slot in `data.value`** — if a point changes from `[x, y, avg_r]` to `[x, y, avg_r, count]`, color silently switches from `avg_r` to `count`. Keep the color-driving metric in `value[2]` and store extra tooltip metadata as sibling keys on the point object (`%{value: [x, y, avg_r], count: count, weekday: weekday, timeslot: slot}`).
20. **Time heatmap tooltips must use `resolveFormatters(option)` for rich metadata** — literal template strings like `{@[2]}` were not interpolated reliably on this chart path. When tooltip content needs `count`, `weekday`, or `timeslot`, pass a sentinel from Elixir and replace it with a real JS formatter in `assets/js/app.js`, reading the sibling fields from `params.data`.
21. **ECharts heatmap `visualMap` at bottom competes with rotated x-axis labels** — both occupy the same vertical space below the grid, causing overlap. Move visualMap above the chart: `top: 5` (in the visualMap) and `grid.top: 40` (in the grid). This is the correct layout for any heatmap where x-axis labels are rotated.
22. **Full-width timeslot heatmaps read better with two-line x-axis labels than rotated labels** — for dense time-bucket heatmaps, format each bucket as `HH:MM\nHH:MM` (for example `09:30\n10:00`) instead of rotating a single string to `90` degrees. This preserves scanability on full-width charts with many columns.
23. **Two-line timeslot x-axis labels need extra bottom grid space** — set `grid.bottom` to about `62` so stacked time labels fit without overlap or clipping. Smaller bottoms reintroduce collisions with the chart edge.
24. **Heatmaps with 14+ x-axis categories must be full-width** — placing a heatmap in a `lg:grid-cols-2` layout halves cell width to ~39px, making labels, cell values, and the visualMap unreadable. Bar charts with 5–12 entries tolerate half-width fine. Apply `col-span-full` or remove grid nesting for any heatmap with many categories.
25. **ECharts dual y-axis requires `yAxis` to be a list, not a map** — `yAxis: %{...}` gives one axis; `yAxis: [%{name: "R", ...}, %{name: "Count", ...}]` gives two. Each series must declare `yAxisIndex: 0` or `yAxisIndex: 1`; omitting it defaults to 0. Use `nameTextStyle: %{align: "left"}` on the right axis to prevent its label from clipping outside the chart.
26. **Bar+line combo charts need `legend.top: 0` + `grid.top: 30`** — without explicit grid top space, the legend overlaps the top of the chart. Standard safe config: `legend: %{top: 0}`, `grid: %{top: 30, bottom: 40, left: 55, right: 55}`.
27. **Bar series item sidecar data is accessed as `barParam.data` in tooltip formatters** — when each bar data point is a map like `%{value: r, timeslot: ts, wins: w, losses: l}`, the tooltip `params` array contains one entry per series; use `params.find(p => p.seriesName === "Total R")` to get the bar entry, then read `barParam.data.wins` etc. For a multi-series axis tooltip, pass a sentinel and resolve it via `resolveFormatters(option)` in `app.js`.

---

## Build Order

### Phase 1 — Foundation (blocks everything else)

1. Check `priv/repo/migrations/` for existing GIN index on `trades.metadata`; create migration if absent
2. Add `assets/package.json` with `echarts` dependency; run `npm install --prefix assets`
3. Configure esbuild in `mix.exs` to include `--node-paths=node_modules`; import `echarts` in `app.js`
4. Add `Hooks.Chart` to `assets/js/app.js`
5. Add `analytics_r_mode` setting helpers to `lib/journalex/settings.ex`
6. Create `lib/journalex/analytics.ex` + `lib/journalex/analytics_behaviour.ex`
7. Add `Mox.defmock(Journalex.MockAnalytics, for: Journalex.AnalyticsBehaviour)` to `test/test_helper.exs`
8. Create shared components: `chart_component.ex`, `analytics_filter_bar.ex`, `kpi_card.ex`
9. Update `nav_helpers.ex` and `app.html.heex` for Analytics section + nav pin
10. Add all 11 routes to `router.ex`

### Phase 2 — Priority Pages

11. A1 — Performance Dashboard (`/analytics/dashboard`)
12. B2 — Trade Calendar Heatmap (`/analytics/calendar`)
13. F1 — Risk / Reward (`/analytics/risk`)

### Phase 3 — Remaining Pages

14. B1 — Equity Curve & Drawdown (`/analytics/equity`)
15. C1 — Breakdown Analysis (`/analytics/breakdown`)
16. D1 — Time Analysis (`/analytics/time`)
17. E1 — Behavioral Flags (`/analytics/behavior`)
18. G1 — Periodic Scorecard (`/analytics/scorecard`)
19. G2 — Streak & Consistency (`/analytics/streaks`)
20. C2 — Ticker Analysis (`/analytics/tickers`)
21. H1 — Period Comparison (`/analytics/compare`)

---

## Changelog

> **Living Document Rule:** This file is the source of truth for the analytics visualization phase. After completing any analytics-related task — implementing a page, establishing a code pattern, discovering a pitfall, creating a component, or making a design decision — append a dated entry to this Changelog section. Future agents and sessions depend on this log to understand what has been built, what patterns are established, and what decisions were made along the way.

### 2026-06-28 — Global analytics exception-day exclusion implemented

**Shared-query rule is now live:** `Journalex.Analytics.base_query/1` excludes configured exception days for every analytics function in one place. No analytics LiveView owns separate state for this filter in this pass.

**Settings storage implemented:** `Journalex.Settings` now persists exception days as a JSON array string of ISO dates, and normalizes blank, duplicate, and unsorted entries on save before analytics reads them back as `Date` structs.

**Date matching rule used in code:** exclusion compares against the stored trade timestamp's database calendar date via `datetime::date`. No market-timezone remapping was added in this pass.

**Settings UI implemented:** `/settings` now exposes repeatable native `type=date` inputs with add/remove controls for exception days.

**LiveView state pattern established:** the settings page now keeps a server-side form snapshot so add/remove row actions do not snap unrelated unsaved fields back to persisted values.

**Tests added:** focused coverage now exists for the shared analytics exclusion path, settings normalization, and the `/settings` save flow for exception days.

### 2026-06-28 — V3 flag alignment and same-version analytics semantics

**Behavior + Scorecard correctness updated for V3 metadata:** `Journalex.Analytics` now has an explicit V3 flag catalog, including `following_rule?` and renamed V3 keys such as `slippage_entry?`, `choppy_chart?`, and `decision_affected_by_other_trade?`.

**Same-version rule established for flag impact:** `flags_impact/1` no longer treats unsupported versions as implicit OFF rows. For each flag, ON/OFF comparison is computed only across trades whose `metadata_version` supports that exact stored key. This prevents V3-only flags from being diluted by V1/V2 rows and keeps renamed V2/V3 flags separate unless a future explicit normalization pass is added.

**Scorecard top_flag updated for V3:** `scorecard_periods/2` now derives `top_flag` from the flag catalog that matches each row's metadata version, so V3-only flags can surface in mixed-version datasets without relying on stale V2 lists.

**Tests added:** Focused regression coverage now exists for:
- V3-only flag `following_rule?`
- Renamed V3 flag `slippage_entry?`
- Mixed-version exclusion from the OFF baseline for version-specific flags

**Deferred on purpose:** multi-select analytics dimensions (`patterns`, `regular_lessons`, `extra_setup_comment`, `good_things`) and humanized flag labels in Behavior/Scorecard remain separate follow-up work.

### 2026-06-28 — Global analytics exception-day exclusion plan

**Refined plan locked:** implement the exclusion once in the shared analytics query so every analytics page inherits it automatically.

**Settings contract:** store exception days in `Journalex.Settings` as a JSON array string of ISO dates, not a comma-separated string.

**Settings UI:** use repeatable native `type=date` inputs with add/remove controls.

**Save-time hygiene:** validate entries, normalize them to ISO format, and deduplicate before persisting.

**Explicitly out of scope for this pass:** no per-page analytics toggle or filter-bar state for exception-day exclusion.

### 2026-06-28 — Breakdown page extended for V3 multi-select dimensions

**New breakdown path for comma-separated metadata fields:** `Journalex.Analytics` now has a dedicated `multi_select_breakdown/2` helper for V3 multi-select fields. It splits comma-separated values, trims whitespace, ignores blanks, and counts each selected option as its own bucket membership instead of treating the whole string as one label.

**Breakdown LiveView now exposes the first multi-select tabs:** `JournalexWeb.Analytics.BreakdownLive` includes `patterns` and `regular_lessons` alongside the existing scalar tabs, and routes those two tabs through the new multi-select helper while leaving the scalar `breakdown_by_dimension/2` path untouched.

**Tests added:** Focused regression coverage now exists for:
- comma-separated bucket splitting and multi-bucket membership
- whitespace trimming and empty-segment filtering
- render-visible Breakdown LiveView tabs for `patterns` and `regular_lessons`

**Deferred on purpose:** `extra_setup_comment` and `good_things` stay out of this pass until the first multi-select rollout is validated in the UI and test suite.

### 2026-04-23 — Planning session complete

- Full analytics plan established: 11 pages across 8 categories (A–H)
- Chart library selected: **ECharts (Apache)** via npm in `assets/`
- All locked decisions recorded above
- Architecture documented: Hooks.Chart pattern, Analytics context signatures, JSONB query patterns, version filter design, R-multiples flow
- Component plan: ChartComponent, AnalyticsFilterBar, KpiCard
- Build order: Phase 1 (foundation) → Phase 2 (Dashboard, Calendar, Risk/Reward) → Phase 3 (remaining 8 pages)
- `analytics_r_mode` added to Settings plan (not yet implemented)
- Priority order confirmed: A1 → B2 → F1

### 2026-04-23 — Post-Phase-2 fixes, nav trim, InfoTooltip

**Bug fixed:** All 3 live analytics LiveViews had `alias JournalexWeb.{...}` for component modules. `<.chart />` syntax requires `import`, not `alias`. Fixed by replacing `alias` with `import JournalexWeb.ChartComponent` etc. in all three `.ex` files.

**Bug fixed:** `lib/journalex/analytics.ex` `base_query/1` used `fragment("(?->>'done??')::boolean = true", t.metadata)`. The `??` approach does not escape `?` in Ecto — each `?` is a placeholder. Correct form: `fragment("(?->>?)::boolean = true", t.metadata, "done?")`.

**Docker:** `elixir:latest` has no Node.js. Added NodeSource `setup_20.x` to Dockerfile to install Node 20 LTS with npm. Added `npm install --prefix assets` to docker-compose web startup command.

**Nav trimmed:** Mega-menu analytics section reduced to 3 live pages (Dashboard, Trade Calendar, Risk / Reward). Stub pages removed from `@all_pages` in `nav_helpers.ex`. Desktop mega-menu redesigned as a 2-column grid.

**New component:** `InfoTooltip` — `lib/journalex_web/live/components/info_tooltip.ex`. Pure CSS hover tooltip (ⓘ icon, Tailwind `group-hover:opacity-100`). Added to all 3 live analytics pages. `KpiCard` updated with optional `tooltip` attr.

**Current state:** Phase 1 + 2 complete and compiling. 3 live pages with full UI, filter bar, ECharts, and tooltips. 8 stub pages remain.

**New files created:**
- `assets/package.json` — ECharts `^5.6.0` dependency
- `lib/journalex/behaviours/analytics_behaviour.ex` — 14 callbacks with precise typespecs
- `lib/journalex/analytics.ex` — Full `@behaviour Journalex.AnalyticsBehaviour` context; `kpi_summary/1`, `equity_curve/1`, `calendar_heatmap/2`, `rr_analysis/1` fully implemented; 9 functions stubbed with `# TODO`
- `lib/journalex_web/live/components/chart_component.ex` — `<.chart>` function component
- `lib/journalex_web/live/components/kpi_card.ex` — `<.kpi_card>` function component
- `lib/journalex_web/live/components/analytics_filter_bar.ex` — `<.analytics_filter_bar>` function component
- `lib/journalex_web/live/analytics/dashboard_live.ex` + `.html.heex` — A1 fully wired: KPI strip + equity curve, filter events, YTD default
- `lib/journalex_web/live/analytics/calendar_live.ex` + `.html.heex` — B2 fully wired: ECharts calendar+heatmap
- `lib/journalex_web/live/analytics/risk_live.ex` + `.html.heex` — F1 fully wired: histogram + scatter, V2-only badge
- 8 stub LiveViews (equity, breakdown, tickers, time, behavior, scorecard, streaks, compare) — each with filter event handlers, pending `.html.heex` placeholders

**Existing files edited:**
- `assets/js/app.js` — `import * as echarts from "echarts"` added; `Hooks.Chart` added (canvas renderer, resize handler, dispose on destroy)
- `config/config.exs` — esbuild `NODE_PATH` extended to include `assets/node_modules`
- `lib/journalex/settings.ex` — `get_analytics_r_mode/0` + `set_analytics_r_mode/1` added; `@default_nav_pinned_pages` updated to include `"analytics_dashboard"`
- `test/test_helper.exs` — `Mox.defmock(Journalex.MockAnalytics, for: Journalex.AnalyticsBehaviour)` added
- `lib/journalex_web/nav_helpers.ex` — 11 analytics page entries added to `@all_pages`
- `lib/journalex_web/router.ex` — 11 analytics routes added under `scope "/", JournalexWeb`
- `lib/journalex_web/components/layouts/app.html.heex` — Analytics section added to both desktop mega-menu and mobile menu

**Next required step:** Run `npm install --prefix assets` to install ECharts before the app will compile JS assets.

**Convention established:** Analytics behaviour file lives at `lib/journalex/behaviours/analytics_behaviour.ex` (not `lib/journalex/analytics_behaviour.ex`).

**NODE_PATH note:** The colon separator in NODE_PATH (`":"`) works inside the Docker Linux container but may not work on Windows host. If running outside Docker, set NODE_PATH via system env instead.

### 2026-04-23 — Calendar heatmap redesign + period presets

**Calendar chart redesigned:** Switched from ECharts `calendar` coordinate system (always shows 7 days) to a Mon–Fri-only category grid heatmap. X-axis = ISO weeks, Y-axis = Mon/Tue/Wed/Thu/Fri. Weekend columns eliminated.

**No-trade day visual:** Past Mon–Fri weekdays with no trades rendered as diagonal-striped grey cells using `itemStyle.decal`. Requires both `aria: %{enabled: true}` in the option map AND `renderer: "canvas"` in `echarts.init`. `visualMap` is a list `[vm0, vm1]`: vm0 targets series 0 (`show: false`, grey), vm1 targets series 1 (R gradient).

**Period presets added:** `JournalexWeb.Analytics.PeriodHelpers.period_to_dates/1` handles 8 period types. Filter bar rewritten with two rows: Row 1 = preset pills + month/week selects; Row 2 = version/dates/R/Reload. All 3 live LiveViews handle `"set_period"` event.

**Chart update architecture solidified:** `phx-update="ignore"` on all chart divs. Chart data delivered via `push_event("chart-update", %{id:, option:})` server-side; JS hook receives via `handleEvent("chart-update", ...)`. No `updated()` callback. `push_event` must be the **return value** of `reload/2` (it returns the socket, so the last call must be `push_event`).

**`filter_dates` form changed to `phx-submit`** — prevents chart reload on every keystroke in date inputs.

### 2026-04-23 — Calendar heatmap rendering bug fix

**Root cause 1 — SVG renderer blocks decals:** ECharts decal patterns (`itemStyle.decal`) are silently ignored when using the SVG renderer. Fixed by changing `echarts.init(el, null, { renderer: "canvas" })` in `assets/js/app.js`. Affects all charts app-wide.

**Root cause 2 — Missing visualMap for series 0:** A heatmap series with no associated `visualMap` entry is completely invisible. The prior config had a single `visualMap` map with `seriesIndex: [1]`, leaving series 0 (no-trade cells) unrendered. Fixed by changing `visualMap` from a single map to a list `[vm0, vm1]`: vm0 targets series 0 with `show: false` and a single grey color; vm1 targets series 1 with the R gradient.

**Root cause 3 — Redundant per-item color:** `no_trade_data` items previously had explicit `itemStyle.color: "#e5e7eb"`. Removed since vm0 now owns the grey color; having both caused a conflict.

### 2026-04-24 — Phase 3 complete: all analytics LiveViews implemented

**Analytics context fully implemented:** All functions in `lib/journalex/analytics.ex` are now implemented (no more `# TODO` stubs): `equity_curve/1`, `streak_data/1`, `breakdown_by_dimension/2`, `long_vs_short/1`, `flags_impact/1`, `time_heatmap/2`, `day_of_week_breakdown/1`, `monthly_breakdown/1`, `scorecard_periods/2`, `ticker_summary/1`.

**All 9 remaining analytics LiveViews implemented:** Equity (`equity_live.ex`), Streaks (`streaks_live.ex`), Breakdown (`breakdown_live.ex`), Scorecard (`scorecard_live.ex`), Time (`time_live.ex`), Tickers (`tickers_live.ex`), Behavior (`behavior_live.ex`), and Period Comparison (`compare_live.ex`).

**HEEx pitfalls encountered:**
- Bare `if` inside list literals (e.g., ECharts option maps built inline) causes SyntaxError — wrap with `if(cond, do: ..., else: ...)` including the comparison inside the parens
- `<%# comment %>` is deprecated in HEEx and treated as warning-as-error — replaced with `<%!-- comment --%>`

**ECharts formatter sentinel pattern established:** Since Elixir option maps are JSON-serialised before reaching the JS hook, JS functions cannot be included. Pattern: put a sentinel string in the option map (e.g., `tooltipFormatter: "heatmap_date"`); define `resolveFormatters(option)` in `app.js` that detects known sentinels and replaces them with real JS functions; call `resolveFormatters(option)` inside `Hooks.Chart` before `chart.setOption(option)`.

**Period Comparison page pattern (`compare_live.ex`):** Two independent filter forms with separate `phx-submit` event names (`"filter_a"` / `"filter_b"`), each calling a shared `reload/2` helper with different date opts. Equity curves from both periods are re-zeroed to their respective period start values before overlay so the chart Y-axis represents R gained within each period rather than all-time cumulative R.

### 2026-04-28 — Time analysis heatmap fixes

**ECharts `{c}` formatter bug:** Heatmap series with multi-value data arrays (e.g., `[xi, yi, avg_r, count]`) rendered the entire array as a comma-joined string when `{c}` was used in cell labels or tooltips. Fixed by switching to `{@[2]}` to target the third element. Cell labels disabled with `label: %{show: false}` where not needed.

**Heatmap color regression guard:** Changing point data from `[xi, yi, avg_r]` to `[xi, yi, avg_r, count]` made `visualMap` color by `count`, because it uses the last numeric slot in `value`. The safe pattern is to keep `avg_r` in `value[2]` and move `count`, `weekday`, and `timeslot` to sibling fields on each point.

**Tooltip formatter correction:** Time heatmap tooltips on this path should use the formatter sentinel pattern via `resolveFormatters(option)` in `assets/js/app.js`. Literal `{@[2]}` template strings were not interpolated reliably here, so rich tooltip content must read sibling fields from `params.data` in a real JS formatter.

**visualMap / x-axis label collision:** Moving `visualMap` to `top: 5` and setting `grid.top: 40` eliminated the overlap with rotated x-axis labels at the bottom of the chart.

**Two-line timeslot axis labels:** On full-width time heatmaps with many x-axis buckets, labels are more readable as two stacked times like `09:30\n10:00` than as a single rotated label. This keeps the axis scannable without resorting to `rotate: 90`.

**Bottom grid spacing for stacked labels:** `grid.bottom: 62` gives two-line timeslot labels enough room without reintroducing overlap or clipping at the chart edge.

**Full-width requirement for heatmaps:** Time heatmaps were placed in `lg:grid-cols-2`. At half width, cell size dropped to ~39px, making all content unreadable. Changed to full-width. Bar charts in the same page (5–12 entries) remain in the grid layout.

### 2026-04-28 — Timeslot performance bar+line charts

**`Analytics.timeslot_breakdown/2` added:** Groups trades by a JSONB timeslot field, returns `{ts, total_r, avg_r, wins, losses}` 5-tuples sorted by timeslot string. Uses `fragment("?->>?", t.metadata, ^field)` for JSONB string extraction — `^field` is bound so `?` in the field name (there is none here, but the pattern is safe for any key).

**Two bar+line combo charts wired into `time_live.ex`:** Entry timeslot chart (always visible) and close timeslot chart (V2-gated with amber warning box, consistent with heatmap section pattern). Charts inserted between the heatmaps and the DoW/Monthly grid in `time_live.html.heex`.

**Dual y-axis ECharts pattern confirmed:** `yAxis` must be a list when using two axes. Bar series uses `yAxisIndex: 0` (Total R), line series uses `yAxisIndex: 1` (Avg R). `nameTextStyle.align` on the right axis keeps the axis label inside the chart boundary.

**Bar+line layout:** `legend: %{top: 0}` + `grid: %{top: 30}` prevents the legend from overlapping chart content. This is the standard config for any dual-series bar+line chart.

**Per-bar item colors:** Set via `itemStyle: %{color: "..."}` inside each data point map in the series data list (not at the series level). Positive total-R bars green, negative bars red.

**Sidecar data on bar items:** Each data point is a map `%{value: r, timeslot: ts, wins: w, losses: l}`. In the `timeslot_breakdown` tooltip formatter (sentinel resolved in `app.js`), `params.find(p => p.seriesName === "Total R").data` gives access to `wins` and `losses` alongside the bar value.

**`timeslot_breakdown` sentinel added to `resolveFormatters`:** New entry `"timeslot_breakdown"` in `app.js` `resolveFormatters`. Uses `params.find(p => p.seriesName === "...")` to extract each series' params independently in the multi-series axis tooltip.

### 2026-04-29 — `time_live.ex` async refactor + convention violations fix

**Blocking `mount/3` fixed:** Replaced inline `reload/2` call with `if(connected?(socket), do: reload(socket, []), else: socket)`. The `connected?` guard prevents DB queries during the server-side dead render.

**`reload/2` now returns `start_async`:** All 6 Analytics DB queries (`time_heatmap`, `timeslot_breakdown` ×2, `day_of_week_breakdown`, `monthly_breakdown` ×2) are batched inside a single `compute_chart_data/1` function called from a `start_async(socket, :load_charts, ...)` task. `handle_async(:load_charts, {:ok, ...}, socket)` builds all chart options and pushes events; `handle_async(:load_charts, {:exit, _}, socket)` puts a flash error.

**`has_v2` computed synchronously before `start_async`:** When a version gate (`has_v2`) drives conditional rendering of entire chart sections, compute it from `a.selected_versions` at the top of `reload/2` (before spawning the task) so the gate reflects the user's filter selection immediately — not after the async result arrives.

**Valid empty chart options required:** Initial chart assigns in `mount/3` must come from empty option builders that still include the required ECharts axes/grid/legend structure. Placeholder maps with only `series` are not sufficient for heatmap, bar, or dual-axis charts.

**SKILL.md fix:** `yAxisIndex: 1` series description corrected from `(count)` to `(Avg R)` in the dual-axis bar+line section.

### 2026-04-28 — `time_live.ex` empty option regression fix

**Browser-confirmed root cause:** `/analytics/time` charts stopped loading because the first render passed invalid empty ECharts options to `Hooks.Chart`. Example bad shape: `%{series: [%{type: "heatmap", data: []}]}`. ECharts raised `xAxis "0" not found`, which crashed `mounted()` before `handleEvent("chart-update", ...)` was registered.

**Fix applied in `time_live.ex`:** `mount/3` now seeds initial chart assigns via `build_timeslot_heatmap_option([])`, `build_timeslot_breakdown_option([])`, `build_dow_option([])`, and `build_monthly_option([])`. All empty-option builders now return valid configs with the required axes, grid, tooltip, legend, and dual-axis structure where applicable.

**Why this matters with `phx-update="ignore"`:** When the hook crashes on the initial empty option, later server `push_event("chart-update", ...)` updates are effectively lost because the handler was never attached. Valid empty configs are therefore required even when real data will arrive asynchronously moments later.

**Behavioral validation:** Verified in the browser that `/analytics/time` now mounts all chart canvases on first load, and remains stable when filters produce empty datasets (e.g. toggling off the only selected version).

### 2026-04-30 — Duration Band Performance chart (`/analytics/time`)

**New function `Analytics.duration_band_breakdown/1`:** Added to `analytics.ex` and `analytics_behaviour.ex`. Queries `{t.duration, t.result, t.realized_pl}` (plain integer column — no JSONB fragment needed). Groups Elixir-side into 7 bins via a `@duration_bins` module attribute list: `[{900, "0–15m"}, {1800, "15–30m"}, {3600, "30–60m"}, {5400, "60–90m"}, {7200, "90–120m"}, {10800, "120–180m"}, {:infinity, "180m+"}]`. Returns `[{bin_label, total_r, avg_r, win_rate, wins, losses}]` 6-tuples. `win_rate` is a 0.0–1.0 float (multiplied by 100 in the option builder, not in the context).

**`@duration_bins` module attribute pattern:** Store duration (or any fixed ordered classification) bins as a module attribute list of `{threshold, label}` tuples. The sentinel `{:infinity, label}` as the last entry means `bin_label/1` needs no `else` branch — `Enum.find_value/2` will always match it. Sorting results by bin order uses `Enum.find_index(@duration_bin_labels, &(&1 == label))`.

**Chart design:** Full-width dual-axis bar+line. Bars = Total R (yAxisIndex 0, green positive / red negative), line = Win Rate % (yAxisIndex 1, right axis `min: 0, max: 100`, blue `#3b82f6`). Win Rate chosen over Avg R as the line metric because it is dimensionless (immune to R/$/Both toggle). No V2 gate — `duration` is a native column present on all metadata versions.

**`"duration_band"` tooltip sentinel:** New entry in `resolveFormatters` in `assets/js/app.js`. Reads `avg_r`, `wins`, `losses` from bar sidecar (`barParam.data`), win rate % from line series value. Output: `{bin}<br/>Total R: {x}<br/>Avg R: {y}<br/>Win Rate: {z}%<br/>Trades: {n} ({w}W / {l}L)`.

**`time_live.ex` changes:** `mount/3` seeds `duration_option` via `build_duration_band_option([])`. `compute_chart_data/1` extended from 6-tuple to 7-tuple, adding `duration_band_breakdown(opts)`. `handle_async(:load_charts, {:ok, 7-tuple}, socket)` assigns `duration_option` and pushes `"chart-update"` for `"duration-band-chart"`.

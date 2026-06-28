# Journalex — Copilot Instructions

## Project overview

Single Phoenix 1.8 + LiveView 1.0 application for tracking IBKR trading activity and syncing trade metadata with Notion.

**Stack:**
- Elixir ~1.18 / Phoenix 1.8 / Phoenix LiveView 1.0
- Bandit HTTP server (not Cowboy)
- Ecto 3.x / PostgreSQL
- Tailwind CSS 3.4.3 + Heroicons v2.1.1 / esbuild 0.17.11
- Finch (HTTP client for Notion API)
- NimbleCSV (IBKR CSV parsing)
- Mox 1.2 (test mocks)
- Tidewave 0.5 (dev-only MCP server)

---

## Directory layout

```
lib/journalex/         ← business logic, contexts, schemas
lib/journalex_web/     ← router, controllers, LiveViews, components
lib/journalex_web/live/            ← LiveView modules
lib/journalex_web/live/components/ ← shared LiveView function components
lib/journalex_web/components/      ← core_components + layouts
lib/journalex/trades/metadata/     ← V1 + V2 embedded metadata schemas
lib/journalex/behaviours/          ← Behaviour modules for Mox
lib/journalex/notion/              ← Notion HTTP client + datasource registry
priv/repo/migrations/              ← Ecto migrations (timestamped)
test/journalex/                    ← unit/context tests
test/support/                      ← DataCase, ConnCase, fixtures
```

---

## Critical architectural patterns

### 1. Behaviour-backed contexts (ALWAYS follow this)

Context modules implement `@behaviour` for Mox testability. **Not all** public functions are declared as callbacks yet — only those needed by LiveView tests have `@callback` entries:

| Context | Behaviour module |
|---|---|
| `Journalex.Activity` | `Journalex.ActivityBehaviour` |
| `Journalex.Trades` | `Journalex.TradesBehaviour` |
| `Journalex.Settings` | `Journalex.SettingsBehaviour` |
| `Journalex.ActivityStatementParser` | `Journalex.ParserBehaviour` |
| `Journalex.CombinedDrafts` | `Journalex.CombinedDraftsBehaviour` |
| `Journalex.WriteupDrafts` | `Journalex.WriteupDraftsBehaviour` |

After adding a `@callback` to a behaviour, **also** add a matching `Mox.defmock` stub in `test/test_helper.exs` — the six mocks currently defined are:

```elixir
Mox.defmock(Journalex.MockActivity, for: Journalex.ActivityBehaviour)
Mox.defmock(Journalex.MockTrades, for: Journalex.TradesBehaviour)
Mox.defmock(Journalex.MockSettings, for: Journalex.SettingsBehaviour)
Mox.defmock(Journalex.MockParser, for: Journalex.ParserBehaviour)
Mox.defmock(Journalex.MockWriteupDrafts, for: Journalex.WriteupDraftsBehaviour)
Mox.defmock(Journalex.MockCombinedDrafts, for: Journalex.CombinedDraftsBehaviour)
```

The mocks exist for future LiveView test isolation. Currently, the only LiveView test (`ActivityStatementUploadResultLiveTest`) calls real modules with CSV fixtures and a real DB. When writing new LiveView tests that need isolation, use `Mox.expect/3` or `Mox.stub/3` with these mocks.

### 2. Polymorphic JSONB metadata

Trades have a single `metadata` JSONB column discriminated by `metadata_version` (integer).

| Version | Module | When used |
|---|---|---|
| 1 | `Journalex.Trades.Metadata.V1` | Legacy Notion structure; 6 boolean flags; V1-specific fields like `follow_setup?`, `follow_stop_loss_management?`, `unnecessary_trade?` |
| 2 | `Journalex.Trades.Metadata.V2` | Legacy-supported structure for older records; 28+ boolean flags; adds `initial_risk_reward_ratio`, `best_risk_reward_ratio`, `size`, `order_type`, `close_timeslot` |
| 3 | `Journalex.Trades.Metadata.V3` | Current production structure; 41 boolean flags (added `random_intraday_trend?` May 2026); `size_in_r` + `r_value` replace `size`; 5 multi_selects; 5-option rank (no "BAD Trade"); 7-option setup; `entry_timeslot`/`close_timeslot` selects, with V3 `close_timeslot` stored in metadata; Phase-0 Notion renames required before sync works |

Entry points:
- `Trades.cast_polymorphic_metadata/2` — routes to the correct embedded schema based on `metadata_version`; use for version-changing writes
- `Trades.update_metadata/2` — partial merge that preserves existing version; use for field updates that don't change version
- `Trades.update_trade/2` with `%{journal_data: ...}` — saves app-only data (progression chain) without touching Notion-mirrored metadata

The `journal_data` JSONB column (added in migration `20260522100000`) stores app-owned data. Currently used for:
- `progression_chain` — list of string tokens (e.g., `["ENTRY", "W25", "TARGET"]`) representing trade lifecycle. Valid tokens: `ENTRY`, `W25`, `W50`, `W75`, `L25`, `L50`, `L75`, `TARGET`, `STOPLOSS`, `MANUAL_WIN`, `MANUAL_LOSE`, `BREAKEVEN`

For V3 push-to-Notion flows, `progression_chain` is still owned by `journal_data`, but it is also mirrored to the Notion rich_text property `"ProgressionChain"` as a backup using arrow serialization such as `ENTRY→W25→TARGET`.

Never mix fields across metadata versions. Never add new fields to V1 (it is legacy). New metadata fields go into V3 only.

### 3. Atom ↔ string key discipline

- **Ecto** returns JSONB maps with **string keys** (e.g., `%{"done?" => true}`)
- **Notion extractors** (`Notion.get_checkbox/2`, etc.) return **atom keys** (e.g., `%{done?: true}`)
- Before merging atom-keyed maps into Ecto changesets, convert with `Atom.to_string/1` (or `Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)`)
- **Never** use `String.to_atom/1` or `String.to_existing_atom/1` on untrusted/external input

### 4. Notion API specifics

- API version header: `Notion-Version: 2025-09-03` (non-public, extended API)
- Query endpoint: `/v1/data_sources/{id}/query` (not standard `/v1/databases/{id}/query`)
- Page parent type: `"data_source_id"` (not `"database_id"`)
- Datasource routing: `Journalex.Notion.DataSources` maps Notion datasource IDs → `metadata_version` integers (1, 2, or 3); routing is automatic during sync — never hardcode version checks in LiveViews
- **Both V1 and V2 use CamelCase Notion property names** (no spaces). The only exception is V1's `"Entry Timeslot"` (has a space), while V2 uses `"EntryTimeslot"` (no space) and adds `"CloseTimeslot"`
- V1-only properties: `"Entry Timeslot"`, `"FollowSetup?"`, `"FollowStopLossManagement?"`, `"UnnecessaryTrade?"`
- V2-only properties: `"EntryTimeslot"`, `"CloseTimeslot"`, `"InitialRiskRewardRatio"`, `"BestRiskRewardRatio"`, `"Size"`, `"OrderType"` and all the extended boolean flags
- Shared property names (same in both): `"Done?"`, `"LostData?"`, `"Rank"`, `"Setup"`, `"CloseTrigger"`, `"RevengeTrade?"`, `"FOMO?"`, `"OperationMistake?"`, `"CloseTimeComment"`

Notion sync helpers in `Journalex.Notion`:
- `get_checkbox/2`, `get_select/2`, `get_number/2` — extract from Notion page properties
- `get_rollup_first_select/2`, `get_multi_select_text/2`
- `maybe_put_select/3`, `maybe_put_checkbox/3`, `maybe_put_number/3`, `maybe_put_multi_select/3` — build Notion property maps
- Note: `get_rich_text/2` and `maybe_put_rich_text/3` have been removed (unused); do not reference them

### 5. Settings

Use `Journalex.Settings` for user-configurable settings (DB-backed, changeable at runtime). `Application.get_env` is acceptable for infrastructure config (API tokens, data source IDs) that comes from `config/runtime.exs`.

The main typed helpers: `Settings.get_default_metadata_version/0`, `Settings.set_default_metadata_version/1`, `Settings.get_r_size/0`, `Settings.get_auto_check_on_load/0`, `Settings.get_activity_page_size/0`, `Settings.get_filter_visible_weeks/0`.

### 6. Docker / ports

| Service | Port |
|---|---|
| Dev database | 6543 (host) → 5432 (container) |
| Dev web | 4008 |
| Test database | 6544 (host) → 5432 (container) |

Never hardcode `5432` in any config or connection string.

---

## LiveView conventions

All LiveViews live under `lib/journalex_web/live/`. Naming: `<Feature>Live` module → `<feature>_live.ex` file.

Standard structure:

```elixir
defmodule JournalexWeb.FeatureLive do
  use JournalexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, key: initial_value)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("event_name", %{"key" => value}, socket) do
    {:noreply, socket}
  end
end
```

- Register the route in `lib/journalex_web/router.ex` under the `scope "/", JournalexWeb` block using `live "/path", FeatureLive`
- Use `assign/2` or `assign/3` — never mutate socket assigns directly
- Use `handle_info/2` for PubSub or async task results

---

## Component conventions

Shared LiveView function components live in `lib/journalex_web/live/components/`. They use `attr` declarations and `slot` for composition. Example:

```elixir
defmodule JournalexWeb.MyComponent do
  use JournalexWeb, :live_component  # or :html for pure function components

  attr :item, :map, required: true
  attr :on_save_event, :string, required: true

  def my_component(assigns) do
    ~H"""
    ...
    """
  end
end
```

The `MetadataForm` component renders V1 or V2 forms via separate function components `v1/1` and `v2/1` based on the trade's `metadata_version`.

---

## Testing conventions

- **`DataCase`** — for context/schema tests that touch the DB (uses Ecto SQL sandbox in manual mode)
- **`ConnCase`** — for controller/HTTP tests
- Use `Mox.expect/3` for strict "this must be called once" expectations, `Mox.stub/3` for lenient setup
- Always `import Mox` and call `verify_on_exit!` in the test module or via DataCase/ConnCase
- Test return values: prefer `assert {:ok, result} = SomeContext.do_thing(...)` pattern
- CSV fixtures: use helpers in `test/support/fixtures.ex` — **do not** read arbitrary files; the whitelist and environment check guards must be respected
- Test files go under `test/journalex/` matching the `lib/journalex/` path

---

## Migration conventions

- Generate with `mix ecto.gen.migration <name>` (produces a timestamped file in `priv/repo/migrations/`)
- Always use `change/0` for reversible migrations; use `up/0` + `down/0` only when `change/0` cannot express the reversal
- Always include `timestamps()` on new tables
- For JSONB columns that will be queried, add a GIN index: `create index(:table, [:column], using: :gin)`
- Column naming: snake_case; boolean columns end with `?` in Elixir schema fields (but NOT in DB column names — Postgres columns use plain snake_case, e.g., `done` not `done?`)

---

## Common pitfalls to avoid

1. Do not use `String.to_atom/1` or `String.to_existing_atom/1` on any Notion API response data
2. Do not add new fields to `Journalex.Trades.Metadata.V1` — it is legacy-frozen
3. Do not hardcode Notion datasource IDs anywhere; always use `Journalex.Notion.DataSources`
4. Do not hardcode port `5432` — use `6543` (dev) or `6544` (test) on the host side
5. Do not use `Cowboy` — Bandit is the HTTP server
6. Do not use `Application.get_env/2` for user-configurable settings — use `Journalex.Settings` (DB-backed)
7. Mox mocks are defined but not yet widely used in tests — current LiveView tests call real modules
8. Do not use `Map.merge/2` to combine atom-keyed and string-keyed maps without converting first
9. Do not reference `get_rich_text/2` or `maybe_put_rich_text/3` — they have been removed from `Journalex.Notion`
10. Do not hardcode Notion property name strings when adding new fields — check the actual property name in the relevant `extract_v1/v2_metadata_from_properties` and `build_v1/v2_metadata_properties` functions in `lib/journalex/notion.ex`
11. Do not use `alias` to bring function components into scope for `<.my_component />` syntax — use `import`. `alias JournalexWeb.MyComponent` only shortcuts the module name; `<.my_component />` requires `import JournalexWeb.MyComponent` so the function is in scope
12. In Ecto `fragment()`, every `?` character in the SQL string is counted as a bind parameter placeholder — including any `?` inside JSONB key names like `"done?"`. Never embed such key names directly in the fragment string; always pass them as a second bound argument: `fragment("(?->>?)::boolean = true", t.metadata, "done?")`
13. Avoid `elixir:latest` for this repo. It does not include Node.js or npm, and it can drift ahead of the Elixir version declared in `mix.exs` and trigger Mix/runtime failures (for example `Mix.Sync.Lock.switch_file_read/1` under Mix 1.19.5). Pin `Dockerfile` and `Dockerfile.test` to the repo's supported Elixir version (`1.18` currently), then install Node via NodeSource: `curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs` — this bundles npm with Node 20 LTS
14. Do not use bare `if` inside list literals in HEEx — `[..., if cond, do: a, else: b]` is a syntax error. Always use parentheses: `[..., if(cond, do: a, else: b)]`. Complex conditions must also move the comparison inside: `if(Map.get(m, :k) >= 0, do: ...)` not `if Map.get(m, :k) >= 0, do:`
15. Do not use `<%# comment %>` in HEEx templates — it is deprecated and treated as a warning-as-error. Always use `<%!-- comment --%>` for HEEx comments
16. When a module attribute stores a list of function captures (e.g., a `@checks` registry), use `&__MODULE__.fun/arity` syntax — plain `&fun/arity` is ambiguous at module attribute evaluation time and may not resolve correctly. `&__MODULE__.fun/arity` explicitly names the current module and is always safe
17. OTP 27 warns on matching `0.0` as a float literal in pattern clauses (imprecise float pattern). Avoid adding `0.0` as a separate match clause for JSONB numeric fields — JSONB integers come back as integers (`0`), not floats; use a guard `when value == 0.0` if a float zero check is genuinely needed
18. Do not perform blocking I/O (HTTP calls, slow Ecto queries, file processing) inside `handle_info/2` or `mount/3` in a LiveView — the LiveView process IS the Phoenix channel GenServer. Blocking it prevents heartbeat processing and causes the client to disconnect with a "view crashed - undefined" error. Use `start_async/3` + `handle_async/3` (Phoenix LiveView 1.0 built-ins) instead
19. Do not use a Notion `rich_text: {equals: ...}` filter to look up Market Daily pages by title — those page titles are Notion **date-mention** rich text (not plain text), so the filter always returns 0 results. `fetch_date_ids` must fetch all pages from the datasource (no title filter) and build the date→ID map from the full result set. `fetch_ticker_ids` is not affected because Ticker Details titles are plain text.
20. Notion's API rejects any `rich_text` span longer than 2000 characters with a 400 error. `BlockBuilder.rich_text/1` handles this automatically by chunking long text into multiple spans (each ≤ 2000 chars). Do not bypass `BlockBuilder` when writing text blocks to Notion.
21. V3 metadata uses `:choppy_chart?` (with underscore). V2 uses `:choppychart?` (no underscore — legacy typo). Never mix these: form param key for V3 is `"choppy_chart"`, for V2 is `"choppychart"`.
22. V3 metadata does **not** have a `"BAD Trade"` rank option. V2 does. When writing code that handles rank values across versions, check the metadata version before assuming valid rank values.
23. Do not use `join_close_time_comments/1` for V3 multi-select fields — use `join_multi_select/1` (same logic, generic name). Both exist in `trades_dump_live.ex` and `metadata_params_builder.ex`.
24. V3 `journal_data` (progression chain) is stored in a separate JSONB column — not in `metadata`. Always use `Trades.update_trade(trade, %{journal_data: ...})` for progression chain updates. Never put `journal_data` keys into the `metadata` map.
25. The progression chain event handlers (`v3_chain_add_token`, `v3_chain_undo`, `v3_chain_clear`) are defined in `trades_dump_live.ex`. If other LiveViews need progression chain editing, they must also implement these handlers independently.
26. Do not use `get_in/2` to read top-level fields from `%Journalex.Trades.Trade{}` (for example `[:journal_data, "progression_chain"]`) inside Notion sync code. Ecto schema structs do not implement `Access`, so this crashes at runtime with `UndefinedFunctionError ... Trade.fetch/2`. Read the struct field with `Map.get(trade, :journal_data)` (or string-key fallback when needed), then read nested map keys with `Map.get/2`.
27. `trade_draft_live.ex` has its own `@supported_versions` list and its own template `case @form_version do` block — separate from `metadata_draft_live.ex`. When adding a new metadata version, update **both** files: `@supported_versions`, the template case, and the bulk version `<select>` options. Also update `config.exs` `:default_metadata_version` and the comment.
28. When removing a Notion field from V3 sync, keep the field in the Ecto embedded schema — JSONB is non-destructive and historical records preserve their data. Only remove from `extract_v3_metadata_from_properties/1`, `build_v3_metadata_properties/1`, `metadata_diff_fields(3)`, and the UI (`v3_flag_groups/0` in `metadata_form.ex`). Never drop the field from the schema on a sync-only removal.
29. Adding or removing a V3 boolean field requires updating exactly 6 locations: (1) `v3.ex` — field declaration, `@boolean_fields`, and `cast/3`; (2) `notion.ex` — `extract_v3_metadata_from_properties/1`; (3) `notion.ex` — `build_v3_metadata_properties/1`; (4) `notion.ex` — `metadata_diff_fields(3)` — so Check Notion diffs include the new field; (5) `metadata_form.ex` — `v3_flag_groups/0` defp function; (6) `trades_dump_live.ex` — `build_v3_metadata_attrs/1` AND `metadata_params_builder.ex` — `build_v3/1`.
30. V3 multi_select defaults in `metadata_form.ex` are only a baseline, not a full live option catalog. MCP `query-data-source` / page payloads can confirm property names and types, but they do not reliably expose unused select or multi_select options. When rendering V3 multi_select fields (`close_time_comment`, `extra_setup_comment`, `good_things`, `patterns`, `regular_lessons`), merge the trade's currently saved values into the default option list so synced Notion values remain visible and editable even if the hardcoded arrays lag behind.
31. **App-only V3 boolean fields** (not synced to Notion) are an intentional exception to pitfall #29. They require only 4 locations: (1) `v3.ex`, (2) `metadata_form.ex` — `v3_flag_groups/0`, (3) `trades_dump_live.ex` — `build_v3_metadata_attrs/1`, (4) `metadata_params_builder.ex` — `build_v3/1`. Deliberately omit `notion.ex` `extract_v3_metadata_from_properties/1`, `build_v3_metadata_properties/1`, and `metadata_diff_fields(3)`. Example: `auto_calculate_from_winning_trade?`.
32. When inserting computed values into a JSONB-sourced `metadata_attrs` map before passing it to an Ecto embedded schema `cast/3` (e.g. `MetadataV3.changeset/2`), always use **string keys**. Ecto's `convert_params/1` only converts atom→string when the map's first key is an atom; if the first key is a string (as JSONB maps always are), it returns the map unchanged — any atom-keyed entry is silently dropped and the field stays `nil`. Use `Map.put(attrs, "size_in_r", value)` not `Map.put(attrs, :size_in_r, value)`.
33. Disabled HTML `<input>` elements are NOT submitted with form data — browsers silently omit them. For display-only fields that must still be saved (e.g. a computed `r_value` shown read-only in the form), use a hidden `<input type="hidden" name="field_name" value={@value}>` alongside the visible element. Never rely on a `disabled` or `readonly` display input to carry a value through form submission.
34. The V3 Notion push pipeline (`build_metadata_properties` cond block in `notion.ex`) must handle two nil cases for `SizeInR`/`RValue` as a pair: (1) when both are nil — fill `SizeInR` from `auto_compute_size(row)` AND `RValue` from `Settings.get_r_size()`; (2) when only `RValue` is nil — fill from `Settings.get_r_size()`. `maybe_put_number("RValue", nil)` is a no-op and silently omits the field from the push payload. Semantic invariant: `r_value` is the 1R dollar amount, which equals `Settings.get_r_size()` (cast to float).
35. V3 Check Notion diff and bulk update must use the same **effective** `SizeInR`/`RValue` rules as the push pipeline. Raw DB `nil` vs Notion `nil` is **not** "in sync" when `build_metadata_properties` would synthesize a value (for example via `auto_compute_size(row)` or `Settings.get_r_size()`). `diff_trade_vs_page` must compare those effective values, bulk update must persist any missing computed/fallback V3 values back into DB before pushing, and `update_all_selected` must not rely only on stale `row_inconsistencies` for selected V3 rows that already have page IDs but are still missing effective size/r fields.
36. For current-production metadata migrations, keep schema/cast, form submission, Notion extract/build/diff, and bulk repair/update flows aligned. A V3 change is not complete until all four agree on field name, storage ownership, and fallback semantics.
37. V3 `close_timeslot` is stored in `metadata` and must participate in `metadata_diff_fields(3)`. Do not reuse V2 `action_chain`-derived close-timeslot logic in V3 code.

---

## Agent routing

For every **non-trivial development task**, present an agent selection menu before starting work. Skip the menu only for purely conversational messages, quick factual questions, or single-line lookups.

**Trigger the menu when the request involves any of:**
- Implementing a feature, change, or bug fix
- Reviewing code for correctness or convention violations
- Running or interpreting tests
- Planning or scoping work
- UI/UX analysis or accessibility review

**Menu format** — always present exactly this before acting:

```
Which mode for this task?

0. Default — handle here (no specialist)
1. Reviewer — convention audit (read-only)
2. Verifier — run tests and check compilation
3. Planner-Lite — quick focused plan
4. UI/UX Advisor — accessibility and design review

Reply with a number, or just describe what you need.
```

**After the user replies:**
- **0** or no number given — proceed in the current agent
- **1** → delegate to `journalex-reviewer`
- **2** → delegate to `journalex-verifier`
- **3** → delegate to `planner-lite`
- **4** → delegate to `journalex-ux`
- **Anything else** — treat as clarification of the task, re-evaluate which option fits, then proceed

---

## Session memory and knowledge curation

**During every non-trivial task**, write notable learnings to `/memories/session/` as they arise. Things worth noting:
- New patterns established or agreed upon
- New pitfalls discovered (mistakes made, wrong assumptions corrected)
- Verified facts about the codebase (confirmed baselines, module signatures, working commands)
- Decisions made about architecture or conventions
- User preferences or habits observed

Keep notes short — bullet points or single facts. Create `/memories/session/learnings.md` if it doesn't exist; append to it if it does.

**During every non-trivial task, track which customized agents participated.** This includes any explicitly selected specialist mode and any subagents invoked automatically during the task, such as `journalex-reviewer`, `journalex-verifier`, `planner-lite`, `journalex-ux`, and `journalex-curator`.

**After every non-trivial task completes**, include a short chat section headed `## Agent Report` before the curator section. Keep it simple:
- List only the customized agents that actually stepped in for the task
- Include a one-line purpose for each agent, or say `None` if no customized agents were involved
- Do not include the default in-place agent unless it delegated to a customized agent

**After every non-trivial task completes** (same bar as the agent routing menu: implementing a feature, bug fix, code review, test run, or planning work), invoke `journalex-curator` as a subagent and post the returned report in the chat response, separated by `---` and headed `## Curator Report`. Do this automatically — do not ask the user first.

The curator reads session notes and the git log, decides what is durable and non-duplicate, updates the appropriate permanent files (memory, skills, instructions), and returns a report listing what was persisted and what was skipped.

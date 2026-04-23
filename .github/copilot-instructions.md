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
| 2 | `Journalex.Trades.Metadata.V2` | Current structure; 28+ boolean flags; adds `initial_risk_reward_ratio`, `best_risk_reward_ratio`, `size`, `order_type`, `close_timeslot` |
| 3 | (schema not yet created) | Config-ready in `DataSources` via `:trades_v3_data_source_id`; no `Metadata.V3` module yet |

Entry points:
- `Trades.cast_polymorphic_metadata/2` — routes to the correct embedded schema based on `metadata_version`; use for version-changing writes
- `Trades.update_metadata/2` — partial merge that preserves existing version; use for field updates that don't change version

Never mix V1 fields into a V2 record or vice versa. Never add new fields to V1 (it is legacy). New metadata fields go into V2 only.

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
13. `elixir:latest` Docker image does not include Node.js or npm. Install via NodeSource: `curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs` — this bundles npm with Node 20 LTS

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

**After every non-trivial task completes** (same bar as the agent routing menu: implementing a feature, bug fix, code review, test run, or planning work), invoke `journalex-curator` as a subagent and post the returned report in the chat response, separated by `---` and headed `## Curator Report`. Do this automatically — do not ask the user first.

The curator reads session notes and the git log, decides what is durable and non-duplicate, updates the appropriate permanent files (memory, skills, instructions), and returns a report listing what was persisted and what was skipped.

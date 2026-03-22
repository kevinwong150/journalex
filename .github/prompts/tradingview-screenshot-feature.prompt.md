---
mode: agent
description: Implement auto-capture of predefined TradingView chart screenshots triggered by a button in the trade list UI
---

# Feature: TradingView Chart Screenshot Capture

## Summary

Add a "Capture Screenshot" button to each trade row in the Journalex UI. When clicked, a predefined TradingView chart layout is auto-captured (via Playwright headless browser) and displayed inline in the UI. Screenshots are stored locally on the filesystem — not synced to Notion.

Before starting, re-read the copilot-instructions and relevant instruction files to follow project conventions.

---

## User decisions (already confirmed)

| Question | Answer |
|---|---|
| Trigger | Manual button per trade (can change later) |
| What is "predefined" | Specific TradingView layout/template name (saved in TradingView account) |
| Screenshot destination | Display in Journalex UI only — no Notion upload |
| Automation method | Playwright headless browser (TradingView has no public image API) |
| Service architecture | Separate Node.js Docker service called by Journalex over HTTP |

---

## Architecture

### Component overview

```
[TradesDumpLive] --HTTP POST--> [screenshot_service (Node.js/Playwright)] --> PNG
      |                               |
      |<-- {path: "..."} -------------|
      |
[ScreenshotController] --serves PNG--> browser
```

### New files to create

| File | Purpose |
|---|---|
| `screenshot_service/package.json` | Node.js service manifest |
| `screenshot_service/index.js` | Express + Playwright capture endpoint |
| `screenshot_service/Dockerfile` | Container for the service |
| `lib/journalex/screenshots.ex` | Elixir context: calls Node.js service, saves PNG |
| `lib/journalex/behaviours/screenshots_behaviour.ex` | Behaviour for Mox testability |
| `lib/journalex_web/controllers/screenshot_controller.ex` | Serves PNGs from `priv/uploads/screenshots/` |

### Files to modify

| File | Change |
|---|---|
| `lib/journalex/trades/metadata/v2.ex` | Add optional `screenshot_path` string field |
| `lib/journalex/settings.ex` | Add 3 new settings: `tradingview_layout_name`, `tradingview_default_timeframe`, `tradingview_exchange` |
| `lib/journalex_web/live/settings_live.ex` | Expose the 3 new settings in the UI |
| `lib/journalex_web/live/trades_dump_live.ex` | Add capture button + loading state + screenshot display |
| `lib/journalex_web/router.ex` | Add `GET /screenshots/:trade_id` route |
| `docker-compose.yml` | Add `screenshot_service` container (internal port 4100) |
| `test/test_helper.exs` | Add `Mox.defmock(Journalex.MockScreenshots, for: Journalex.ScreenshotsBehaviour)` |

---

## Implementation plan

### Phase 1 — Screenshot Service (Node.js + Docker)

1. Create `screenshot_service/` directory with `package.json` (deps: `express`, `playwright`)
2. Implement `screenshot_service/index.js`:
   - `POST /capture` accepts `{ ticker, datetime, exchange, interval, layout_name }`
   - On first request, launch Playwright Chromium and login to TradingView using `TRADINGVIEW_USER` / `TRADINGVIEW_PASS` env vars
   - Cache session cookies to `screenshot_service/data/cookies.json` (mounted as Docker volume) to survive container restarts
   - Navigate to: `https://www.tradingview.com/chart/?symbol=<exchange>:<ticker>&interval=<interval>&template=<layout_name>`
   - Wait for the chart candle container selector to confirm render (not a time-based delay)
   - Return `{ image: "<base64 PNG>" }` JSON
3. Create `screenshot_service/Dockerfile` (Node 20-slim + Playwright Chromium)
4. Add to `docker-compose.yml`:
   ```yaml
   screenshot_service:
     build: ./screenshot_service
     environment:
       - TRADINGVIEW_USER
       - TRADINGVIEW_PASS
     volumes:
       - ./screenshot_service/data:/app/data
     networks:
       - app_network
   ```
   Do NOT expose the port to host — only accessible internally on the Docker network.

### Phase 2 — Elixir Context + Behaviour

5. Create `lib/journalex/behaviours/screenshots_behaviour.ex`:
   ```elixir
   defmodule Journalex.ScreenshotsBehaviour do
     @callback capture_for_trade(trade :: map()) :: {:ok, String.t()} | {:error, term()}
   end
   ```

6. Create `lib/journalex/screenshots.ex`:
   - `capture_for_trade/1` — builds the request payload from trade fields, POSTs to `http://screenshot_service:4100/capture` via Finch, decodes base64 PNG, saves to `priv/uploads/screenshots/<trade_id>.png`, returns `{:ok, path}`
   - Read `layout_name`, `interval`, `exchange` from `Journalex.Settings`
   - The screenshot service URL should come from `Application.get_env(:journalex, :screenshot_service_url)` (set in `config/runtime.exs`)
   - Follow the same `@behaviour Journalex.ScreenshotsBehaviour` pattern as other contexts

7. Add to `test/test_helper.exs`:
   ```elixir
   Mox.defmock(Journalex.MockScreenshots, for: Journalex.ScreenshotsBehaviour)
   ```

### Phase 3 — Settings

8. In `lib/journalex/settings.ex`, add three typed helpers following the existing pattern:
   - `get_tradingview_layout_name/0` → string, default `""`
   - `get_tradingview_timeframe/0` → string, default `"5"` (5-minute bars)
   - `get_tradingview_exchange/0` → string, default `"NASDAQ"`

9. In `lib/journalex_web/live/settings_live.ex`, add corresponding form fields for these three settings.

### Phase 4 — UI

10. In `lib/journalex/trades/metadata/v2.ex`, add:
    ```elixir
    field :screenshot_path, :string
    ```
    This is a JSONB subfield — no migration needed.

11. In `lib/journalex_web/live/trades_dump_live.ex`:
    - Add a `"capture_screenshot"` event handler that calls `Journalex.Screenshots.capture_for_trade/1`, updates the trade's `metadata.screenshot_path` via `Trades.update_metadata/2`, and refreshes the socket assign
    - Track per-trade loading state with a `MapSet` or `Map` in socket assigns (e.g., `:capturing_ids`)
    - Render captured screenshot inline if `metadata.screenshot_path` is not nil/empty — use an `<img>` tag pointing to `/screenshots/<trade_id>`
    - The button should be disabled while capture is in progress for that trade

12. Add `ScreenshotController` at `lib/journalex_web/controllers/screenshot_controller.ex`:
    - `show/2` reads trade ID from params, resolves path `priv/uploads/screenshots/<trade_id>.png`, sends file with `send_file/3`
    - Must validate `trade_id` is a valid UUID (reject anything else) to prevent path traversal

13. Register the route in `lib/journalex_web/router.ex`:
    ```elixir
    get "/screenshots/:trade_id", ScreenshotController, :show
    ```

---

## Important constraints (from project conventions)

- **V1 metadata is frozen** — do not add `screenshot_path` to V1; V2 only
- **No `String.to_atom/1`** on any external input (including Playwright/HTTP responses)
- **Atom ↔ string key discipline** — if merging atom-keyed settings maps into Ecto changesets, convert keys first
- **No Cowboy** — Bandit is the HTTP server; do not reference Cowboy
- **Settings are DB-backed** — use `Journalex.Settings`, not `Application.get_env`, for the three TradingView settings
- **Service URL is infra config** — the screenshot service URL (not user-configurable) goes in `config/runtime.exs` via `Application.get_env`
- **Path traversal protection** — validate trade ID before building the file path in `ScreenshotController`
- **`priv/uploads/screenshots/`** — create this directory (or ensure it's created on first save); add `.gitkeep` to track the directory without committing PNGs

---

## Verification checklist

- [ ] `docker compose up screenshot_service` starts without errors
- [ ] `curl -X POST http://localhost:4100/capture -d '{"ticker":"AAPL","exchange":"NASDAQ","interval":"5","layout_name":"my-layout"}' -H 'Content-Type: application/json'` returns base64 PNG
- [ ] Clicking "Capture Screenshot" button in TradesDumpLive shows loading spinner, then renders screenshot inline
- [ ] `priv/uploads/screenshots/<trade_id>.png` exists on disk after capture
- [ ] Changing `tradingview_layout_name` in Settings and re-capturing uses the new layout name
- [ ] Invalid trade ID in `/screenshots/:id` returns 400/404, not a file system error
- [ ] Screenshots context has a matching behaviour + mock registered in `test/test_helper.exs`

---

## Further considerations

- **Manual upload fallback**: If Playwright proves unreliable (TradingView anti-bot measures, DOM changes), add a `<.live_file_input>` fallback on the same button. User manually uploads a PNG; it is stored the same way to `priv/uploads/screenshots/<trade_id>.png`.
- **Session persistence**: TradingView sessions last ~30 days. Persist cookies to the mounted volume (`screenshot_service/data/cookies.json`) so re-login only happens on session expiry.
- **Exchange prefix edge cases**: IBKR tickers don't always map 1:1 to TradingView exchange prefixes (e.g., some OTC or international tickers). The default exchange setting covers the common case; per-trade override is a future enhancement.
- **Concurrent captures**: If multiple trades are captured simultaneously, each Playwright page request should be queued or rate-limited in the Node service to avoid TradingView rate limiting.

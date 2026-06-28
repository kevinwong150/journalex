# Verification — Verified Facts

## Docker Test Workflow

- `docker-compose.test.yml` builds the `test` service from `Dockerfile.test` with COPY steps and no bind mounts
- After source changes, use `docker compose -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from test` or rebuild first; `docker compose -f docker-compose.test.yml run --rm test` alone can validate stale copied code

## Current Baseline

- Docker image baseline (June 2026): `mix.exs` targets `elixir: "~> 1.18"`; keep `Dockerfile` and `Dockerfile.test` pinned to `FROM elixir:1.18` to avoid `elixir:latest` Mix/runtime drift
- Docker rebuild validation (June 2026): `docker compose build --no-cache web` then `docker compose --env-file .env up -d` moves past the old `Mix.Sync.Lock.switch_file_read/1` crash into normal dependency compilation; `docker compose -f docker-compose.test.yml build --no-cache` also succeeds on the pinned test image
- Fresh rebuilt test image: 235 tests, 0 failures (April 2026)
- V3 migration complete (Phases 1-11): 92 files compiled, 0 errors/warnings in MIX_ENV=test (May 2026)
- V3 fully wired end-to-end (Notion properties confirmed, docker-compose env var added, compile passes): `default_metadata_version` bumped to `3` in `config.exs` (May 2026)
- `trade_draft_live.ex` V3 form fix: `@supported_versions` updated to `[1, 2, 3]`, V3 case added to template, V3 option added to bulk version select — separate from `metadata_draft_live.ex`
- Web compile with warnings-as-errors passes
- V3 `random_intraday_trend?` boolean added (May 2026): all 5 required locations updated (`v3.ex`, `notion.ex` extract + build, `metadata_form.ex` v3_flag_groups, `trades_dump_live.ex` + `metadata_params_builder.ex`); V3 now has 41 boolean flags total
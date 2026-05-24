# Verification — Verified Facts

## Docker Test Workflow

- `docker-compose.test.yml` builds the `test` service from `Dockerfile.test` with COPY steps and no bind mounts
- After source changes, use `docker compose -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from test` or rebuild first; `docker compose -f docker-compose.test.yml run --rm test` alone can validate stale copied code

## Current Baseline

- Fresh rebuilt test image: 235 tests, 0 failures (April 2026)
- V3 migration complete (Phases 1-11): 92 files compiled, 0 errors/warnings in MIX_ENV=test (May 2026)
- V3 fully wired end-to-end (Notion properties confirmed, docker-compose env var added, compile passes): `default_metadata_version` bumped to `3` in `config.exs` (May 2026)
- `trade_draft_live.ex` V3 form fix: `@supported_versions` updated to `[1, 2, 3]`, V3 case added to template, V3 option added to bulk version select — separate from `metadata_draft_live.ex`
- Web compile with warnings-as-errors passes
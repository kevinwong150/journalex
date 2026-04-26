# Verification — Verified Facts

## Docker Test Workflow

- `docker-compose.test.yml` builds the `test` service from `Dockerfile.test` with COPY steps and no bind mounts
- After source changes, use `docker compose -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from test` or rebuild first; `docker compose -f docker-compose.test.yml run --rm test` alone can validate stale copied code

## Current Baseline

- Fresh rebuilt test image: 235 tests, 0 failures (April 2026)
- Web compile with warnings-as-errors passes
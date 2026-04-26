# Notion Client — Verified Facts

## HTTP Retry

`Journalex.Notion.Client.request_with_retry/5` is the retry wrapper (added post check-flow redesign):
- Max 3 attempts
- Retries on: 429, 502, 503, 504
- Backoff: `500ms × 2^(attempt−1)` ± 40% jitter, capped at 8s
- Used by: `query_database`, `retrieve_page`
- NOT used by mutation functions (`update_page`, `create_page`, `append_block_children`)

## Finch Pool

`receive_timeout: 30_000` (30s) configured in `application.ex`:
```elixir
{Finch, name: Journalex.Finch, pools: %{default: [receive_timeout: 30_000]}}
```

## `Process.sleep` in Tasks

`Process.sleep` is safe inside `start_async` task lambdas — the lambda runs in a separate process, so sleeping does not block the LiveView channel.

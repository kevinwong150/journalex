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

## V3 FollowingRule? Wiring

`FollowingRule?` is a Notion-synced V3 checkbox property. Keep these mappings aligned when touched:
- `following_rule?` in `lib/journalex/trades/metadata/v3.ex`
- `"FollowingRule?"` in `extract_v3_metadata_from_properties/1`, `build_v3_metadata_properties/1`, and `metadata_diff_fields(3)` in `lib/journalex/notion.ex`
- `following_rule` form param handling in `lib/journalex_web/live/trades_dump_live.ex` and `lib/journalex_web/helpers/metadata_params_builder.ex`

---
applyTo: "lib/journalex_web/live/**"
---

# LiveView conventions — Journalex

## Context module usage

LiveViews call context modules directly via aliases:

```elixir
alias Journalex.Activity
alias Journalex.Trades
alias Journalex.Settings
```

This is the current pattern across all existing LiveViews. Context modules are also aliased for Repo, schema, and Notion modules as needed.

## Standard mount/handle structure

```elixir
defmodule JournalexWeb.FeatureLive do
  use JournalexWeb, :live_view

  alias Journalex.Trades
  alias Journalex.Trades.Trade

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, data: [], loading: false)}
  end

  @impl true
  def handle_event("event_name", %{"key" => value}, socket) do
    case Trades.some_function(value) do
      {:ok, result} -> {:noreply, assign(socket, data: result)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  # For async Task results
  @impl true
  def handle_info({ref, result}, socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, data: result)}
  end
end
```

## Rules

- All assigns must be initialised in `mount/3`
- Use `assign/2` or `assign/3` — never mutate socket assigns directly
- Use `handle_info/2` for async Task results — never block in `mount/3`
- Register routes in `lib/journalex_web/router.ex` under `scope "/", JournalexWeb`
- Use `Journalex.Settings` for user-configurable settings (not `Application.get_env` for those)
- Do NOT import `Ecto.Query` in LiveViews — all queries stay in context modules
- Use `import ModuleName` (not `alias`) when a LiveView template uses shorthand component syntax `<.func_name />` — `alias` only shortcuts the module name and does NOT bring the function into scope
- Do NOT use bare `if` inside list literals in HEEx — `[..., if cond, do: a, else: b]` causes a SyntaxError; use `[..., if(cond, do: a, else: b)]` with parentheses
- Do NOT use `<%# comment %>` in HEEx — deprecated, treated as warning-as-error; use `<%!-- comment --%>` instead
- Do NOT perform blocking I/O (HTTP calls, slow Ecto queries, file processing) in `handle_info/2` or `mount/3` — the LiveView process IS the Phoenix channel GenServer; blocking it prevents heartbeat processing and causes client disconnects. Use `start_async/3` + `handle_async/3` instead
- For paginated or sliced collections whose row actions depend on the original row position, preserve caller-provided `{item, global_index}` pairs through sorting and rendering; do NOT re-index inside the child component after pagination
- If select-all or bulk actions are page-scoped in a paginated LiveView, compute them from the visible page subset rather than the full backing list
- When the same control block needs to appear in multiple places within one LiveView, extract it into a local function component so labels, event wiring, and disabled states stay behavior-identical
- For LiveView pages with multiple mutually exclusive UI modes (e.g., bulk-create mode vs select mode), use two boolean assigns as a "toolbar state" controller: each toggle handler resets the other boolean to `false`. Use `:if` blocks in the header area to render the correct toolbar. Example: `bulk_mode` and `select_mode` — toggling `bulk_mode` does `assign(socket, bulk_mode: true, select_mode: false)` and vice versa
- For selection-mode UX: toggle checkbox visibility with `:if={@select_mode}` on each row's `<input>` element (no JS required). Gate the action bar on `@select_mode && MapSet.size(@selected_ids) > 0` to prevent accidental trigger from residual selection state when outside select mode
- For standalone `<input>` / `<select>` controls involved in `phx-change`, always set a `name` attribute and match `handle_event/3` params on that name (for example `%{"version" => value}`), not `%{"value" => value}`. LiveView change payloads are keyed by input name
- Prefer wrapping standalone controls in their own small `<form phx-change=...>` instead of putting `phx-change` directly on the control. Require the wrapper form when the control sets LiveView state that must survive later rerenders from other events (for example bulk selectors followed by add/remove row clicks). Name-only standalone controls proved brittle in real browser paths and can snap back to the assigned default after a later rerender
- When a form or row can rerender from sibling events before save, `phx-change` must store the current normalized form snapshot in assigns and render must prefer that pending snapshot over persisted data until save/reset. A dirty flag alone is not enough; otherwise unrelated rerenders can snap unsaved checkbox/select state back to the last saved values. Preserve readonly fields that browsers omit when rebuilding the snapshot
- Disabled `<input>` elements are NOT submitted by browsers — they are silently omitted from form payloads. For display-only fields that must still be included in form submission (e.g. a computed value shown read-only), use `<input type="hidden" name="field_name" value={@value}>` alongside the visible element. Never rely on a `disabled` input to carry a value through form submission

## Toolbar and button accessibility

- Always add a `title` attribute to every toolbar button, especially icon-only buttons. Button labels alone are often ambiguous in dense toolbars
- For disabled buttons that communicate a reason, use a dynamic `title`: `title={if @connected, do: "Normal description", else: "Waiting for server connection…"}` — provides context without relying on visual cues alone
- Count badge `<span>` elements should have `aria-label` to make the numeric value meaningful to screen readers: `aria-label="{n} drafts"`
- Overflow `<details>/<summary>` elements whose `<summary>` text is a visual placeholder (e.g., `···`) must include `title="More options"` on the `<summary>`
- Menu item labels in overflow dropdowns should use verb-noun phrasing ("New drafts…") not ambiguous shorthand ("Batch new…")

## Confirmation modal pattern (assign-based, not data-confirm)

For destructive actions that require user confirmation — especially those with multiple modes (e.g., shallow vs deep delete) — use an assign to store pending state rather than a `data-confirm` attribute:

```elixir
# Event handler that triggers confirmation
def handle_event("delete", %{"id" => id_str}, socket) do
  {id, _} = Integer.parse(id_str)
  name = find_name(socket, id)
  {:noreply, assign(socket, :my_delete_confirm, %{pending_ids: [id], label: "\"#{name}\""})}
end

# Confirmation handler — mode passed as phx-value-mode from the modal buttons
def handle_event("confirm_delete", %{"mode" => mode_str}, socket) do
  %{pending_ids: ids} = socket.assigns.my_delete_confirm
  mode = if mode_str == "deep", do: :deep, else: :shallow
  socket = assign(socket, :my_delete_confirm, nil)  # dismiss modal first
  # ... perform delete, update assigns, put_toast ...
end

# Cancel handler
def handle_event("cancel_delete", _params, socket) do
  {:noreply, assign(socket, :my_delete_confirm, nil)}
end
```

In the template, render the modal conditionally on the assign being non-nil. Use `data-confirm` only for simple single-action confirmations with no mode variants.

## Async operations — start_async / handle_async

The LiveView process IS the Phoenix channel GenServer. Any blocking I/O inside `handle_info/2` or `mount/3` (HTTP calls, slow DB queries, file processing) blocks the channel process entirely — including heartbeat processing — which causes the client to disconnect with a "view crashed - undefined" error.

**Always** offload blocking work using the built-in `start_async/3` + `handle_async/3` pattern:

```elixir
@impl true
def handle_event("sync", _params, socket) do
  {:noreply, start_async(socket, :my_task, fn -> do_blocking_work() end)}
end

@impl true
def handle_async(:my_task, {:ok, result}, socket) do
  {:noreply, assign(socket, data: result)}
end

def handle_async(:my_task, {:exit, reason}, socket) do
  {:noreply, put_flash(socket, :error, "Task failed: #{inspect(reason)}")}
end
```

- `start_async/3` spawns a linked task and returns immediately
- `handle_async/3` receives the result as `{:ok, value}` or `{:exit, reason}`
- Never use bare `Task.async/1` + `handle_info({ref, result}, ...)` for new code — prefer `start_async`
- The `mount/3` pattern `if connected?(socket), do: send(self(), :load)` is acceptable for lightweight data loads, but any blocking call behind that `:load` message must use `start_async` not a direct call inside `handle_info`
- For heavier loads (e.g., analytics charts), skip the `send/handle_info` hop entirely — call a `reload(socket, opts)` function directly from the `connected?` guard in `mount/3`; that function returns `start_async(socket, :key, fn -> ... end)`. Pattern: `if(connected?(socket), do: reload(socket, []), else: socket)`
- Seed placeholder assigns in `mount/3` so the initial dead render has a defined shape without running any DB query; for charts, prefer the same empty builder used for real data (for example `build_chart_option([])`) instead of an ad hoc module attribute map
- When a chart uses `phx-update="ignore"` with `Hooks.Chart`, its initial option must still be a valid ECharts config for that chart type. Placeholder maps that only contain `series` can crash `mounted()` before `handleEvent("chart-update", ...)` is registered
- For ad hoc action buttons that operate on a specific trade row (e.g., "Compute Size in R", "Reset", one-off triggers), inject the button in the **parent list component** (e.g., `aggregated_trade_list.ex`) immediately before or after the `render_metadata_form` call — do NOT thread extra props through the metadata form component chain just to render a button. The parent already has the trade and idx in scope; keeping the button there avoids prop-drilling and keeps `MetadataForm` props stable

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

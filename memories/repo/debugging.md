# Debugging — Verified Techniques

## "view crashed - undefined" error

This client-side error means the LiveView process crashed or was disconnected. Common causes:
- Blocking I/O in `handle_info/2` or `mount/3` prevented heartbeat processing → channel dropped
- An unhandled exception in `handle_info/2` / `handle_event/3` crashed the process

**Diagnosis checklist:**
1. Check server logs for an Elixir exception — the crash reason appears before the disconnect
2. If no exception logged, suspect a heartbeat timeout from blocking I/O (e.g., an HTTP call running on the LiveView process)
3. Wrap the suspect `handle_info` clause in `try/rescue` temporarily to surface hidden exceptions:

```elixir
def handle_info(:some_message, socket) do
  try do
    result = do_the_thing()
    {:noreply, assign(socket, data: result)}
  rescue
    e -> 
      IO.inspect({e, __STACKTRACE__}, label: "handle_info crash")
      {:noreply, socket}
  end
end
```

4. Remove the `try/rescue` once the root cause is identified — it is diagnostic only.

## Blocking I/O → heartbeat drop

LiveView IS the Phoenix channel GenServer. Any blocking call in the process (including `handle_info`, `handle_event`, or `mount`) blocks ALL message processing. The Phoenix heartbeat ping goes unacknowledged → client disconnects after ~30 s. Fix: use `start_async/3` + `handle_async/3`.

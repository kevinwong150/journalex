defmodule JournalexWeb.QueueProcessor do
  @moduledoc """
  Shared lifecycle helpers for queue-based operations in LiveViews.

  Provides `init_assigns/2`, `start_operation/3`, `finish_operation/2`,
  and `cancel_operation/2` to manage the common assign keys that every
  queue operation uses (queue, total, processed, in_progress?, timer_ref,
  started_at_mono, finished_at_mono, elapsed_ms, current).
  """

  import Phoenix.Component, only: [assign: 3]

  @doc """
  Initialise mount-time assigns for a queue operation prefix.

  Returns the socket with `{prefix}_queue`, `{prefix}_total`, etc. all
  set to their zero/nil defaults. Pass `extra` keyword list for additional
  assigns like `:results`, `:retry_counts`.
  """
  def init_assigns(socket, prefix, extra \\ []) do
    socket
    |> assign(:"#{prefix}_queue", [])
    |> assign(:"#{prefix}_total", 0)
    |> assign(:"#{prefix}_processed", 0)
    |> assign(:"#{prefix}_in_progress?", false)
    |> assign(:"#{prefix}_current", nil)
    |> assign(:"#{prefix}_started_at_mono", nil)
    |> assign(:"#{prefix}_finished_at_mono", nil)
    |> assign(:"#{prefix}_elapsed_ms", 0)
    |> assign(:"#{prefix}_timer_ref", nil)
    |> then(fn socket ->
      Enum.reduce(extra, socket, fn {key, val}, acc -> assign(acc, key, val) end)
    end)
  end

  @doc """
  Set the standard start-of-operation assigns and schedule the first tick.

  `message` is the atom sent via `Process.send_after` (e.g. `:process_next_check`).
  `extra_fn` is an optional function applied to the socket after the standard assigns.
  """
  def start_operation(socket, prefix, queue, message, extra_fn \\ &Function.identity/1) do
    now = System.monotonic_time(:millisecond)

    socket
    |> assign(:"#{prefix}_queue", queue)
    |> assign(:"#{prefix}_total", length(queue))
    |> assign(:"#{prefix}_processed", 0)
    |> assign(:"#{prefix}_in_progress?", true)
    |> assign(:"#{prefix}_current", nil)
    |> assign(:"#{prefix}_started_at_mono", now)
    |> assign(:"#{prefix}_finished_at_mono", nil)
    |> assign(:"#{prefix}_elapsed_ms", 0)
    |> extra_fn.()
    |> then(fn socket ->
      timer_ref = Process.send_after(self(), message, 0)
      assign(socket, :"#{prefix}_timer_ref", timer_ref)
    end)
  end

  @doc """
  Mark an operation as finished — sets in_progress? to false, captures
  elapsed time, and nils the timer ref.  `extra_fn` is applied last.
  """
  def finish_operation(socket, prefix, extra_fn \\ &Function.identity/1) do
    finished_key = :"#{prefix}_finished_at_mono"
    started_key = :"#{prefix}_started_at_mono"
    elapsed_key = :"#{prefix}_elapsed_ms"

    now = System.monotonic_time(:millisecond)

    socket
    |> assign(:"#{prefix}_in_progress?", false)
    |> assign(:"#{prefix}_current", nil)
    |> assign(:"#{prefix}_timer_ref", nil)
    |> assign(finished_key, socket.assigns[finished_key] || now)
    |> assign(elapsed_key,
      if(socket.assigns[started_key],
        do: (socket.assigns[finished_key] || now) - socket.assigns[started_key],
        else: 0
      )
    )
    |> extra_fn.()
  end

  @doc """
  Cancel a running operation — cancels the timer, clears the queue, and
  marks it finished.  `extra_fn` is applied last (e.g. to build dump report).
  """
  def cancel_operation(socket, prefix, extra_fn \\ &Function.identity/1) do
    in_progress_key = :"#{prefix}_in_progress?"
    timer_ref_key = :"#{prefix}_timer_ref"
    queue_key = :"#{prefix}_queue"

    if socket.assigns[in_progress_key] do
      if socket.assigns[timer_ref_key], do: Process.cancel_timer(socket.assigns[timer_ref_key])

      socket
      |> assign(queue_key, [])
      |> finish_operation(prefix, extra_fn)
    else
      socket
    end
  end
end

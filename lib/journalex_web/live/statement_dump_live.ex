defmodule JournalexWeb.StatementDumpLive do
  use JournalexWeb, :live_view

  alias Journalex.Activity
  alias JournalexWeb.ActivityStatementList
  alias Journalex.Notion
  alias Journalex.Notion.Client, as: NotionClient

  @dump_max_retries 3

  @impl true
  def mount(_params, _session, socket) do
    statements = Activity.list_all_activity_statements()

    socket =
      socket
      |> assign(:statements, statements)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:all_selected?, false)
      |> assign(:row_statuses, %{})
      |> assign(:notion_exists_count, 0)
      |> assign(:notion_missing_count, 0)
      |> assign(:notion_conn_status, :unknown)
      |> assign(:notion_conn_message, nil)
      |> assign(:hide_exists?, false)
      # Dump queue/progress state
      |> assign(:dump_queue, [])
      |> assign(:dump_total, 0)
      |> assign(:dump_processed, 0)
      |> assign(:dump_in_progress?, false)
      |> assign(:dump_current, nil)
      |> assign(:dump_results, %{})
  |> assign(:dump_started_at_mono, nil)
  |> assign(:dump_finished_at_mono, nil)
  |> assign(:dump_elapsed_ms, 0)
  |> assign(:dump_retry_counts, %{})

    # Kick off an automatic Notion check after the socket connects
    if connected?(socket), do: send(self(), :auto_check_notion)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_ids = socket.assigns.statements |> Enum.map(& &1.id) |> MapSet.new()

    {selected_ids, all_selected?} =
      if socket.assigns.all_selected? do
        {MapSet.new(), false}
      else
        {all_ids, true}
      end

    {:noreply, assign(socket, selected_ids: selected_ids, all_selected?: all_selected?)}
  end

  def handle_event("toggle_row", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    all_ids = socket.assigns.statements |> Enum.map(& &1.id) |> MapSet.new()
    all_selected? = MapSet.equal?(selected, all_ids) and MapSet.size(all_ids) > 0

    {:noreply, assign(socket, selected_ids: selected, all_selected?: all_selected?)}
  end

  def handle_event("check_notion", _params, socket) do
    selected_ids = socket.assigns.selected_ids
    statements = socket.assigns.statements

    selected_rows = Enum.filter(statements, fn s -> MapSet.member?(selected_ids, s.id) end)

    # New logic: bulk fetch all Notion records and compare via Trademark field
    case Notion.list_all_trademarks() do
      {:ok, trademark_set} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(selected_rows, {%{}, 0, 0}, fn row, {acc, ec, mc} ->
            # Trademark format mirrors creation: "<Ticker>@<ISO8601(datetime)>"
            title = row.symbol <> "@" <> DateTime.to_iso8601(row.datetime)

            if MapSet.member?(trademark_set, title) do
              {Map.put(acc, row.id, :exists), ec + 1, mc}
            else
              {Map.put(acc, row.id, :missing), ec, mc + 1}
            end
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count
         )}

      {:error, reason} ->
        msg = inspect(reason)
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(selected_rows, {%{}, 0, 0}, fn row, {acc, ec, mc} ->
            {Map.put(acc, row.id, :error), ec, mc}
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count,
           notion_conn_status: :error,
           notion_conn_message: "Failed to fetch Notion records: " <> msg
         )}
    end
  end

  def handle_event("insert_missing_notion", _params, socket) do
    # If a dump is already in progress, ignore repeated clicks
    if socket.assigns.dump_in_progress? do
      {:noreply, socket}
    else
      selected_ids = socket.assigns.selected_ids
      statements = socket.assigns.statements
      statuses = socket.assigns.row_statuses || %{}

      # Build the queue: prefer rows currently marked as :missing; otherwise include all selected
      # We will still double-check existence per item before creation to be safe.
      selected_rows = Enum.filter(statements, fn s -> MapSet.member?(selected_ids, s.id) end)

      missing_rows = Enum.filter(selected_rows, fn r -> Map.get(statuses, r.id) == :missing end)
      queue = if missing_rows == [], do: selected_rows, else: missing_rows

      socket =
        socket
        |> assign(:dump_queue, queue)
        |> assign(:dump_total, length(queue))
        |> assign(:dump_processed, 0)
        |> assign(:dump_in_progress?, true)
        |> assign(:dump_current, nil)
        |> assign(:dump_results, %{})
        |> assign(:dump_started_at_mono, System.monotonic_time(:millisecond))
        |> assign(:dump_finished_at_mono, nil)
        |> assign(:dump_elapsed_ms, 0)
        |> assign(:dump_retry_counts, %{})

      # Kick off the first tick immediately; subsequent ticks run every 1s
      Process.send_after(self(), :process_next_dump, 0)

      {:noreply, socket}
    end
  end

  def handle_event("clear_row_statuses", _params, socket) do
    {:noreply,
     assign(socket,
       row_statuses: %{},
       notion_exists_count: 0,
       notion_missing_count: 0
     )}
  end

  def handle_event("toggle_hide_exists", _params, socket) do
    {:noreply, assign(socket, hide_exists?: !socket.assigns.hide_exists?)}
  end

  def handle_event("check_notion_connection", _params, socket) do
    user_res = NotionClient.me()

    notion_conf = Application.get_env(:journalex, Journalex.Notion, [])
    ds_id = Keyword.get(notion_conf, :data_source_id)
    db_res = if ds_id, do: NotionClient.retrieve_database(ds_id), else: {:ok, :no_db_configured}

    case {user_res, db_res} do
      {{:ok, _user}, {:ok, :no_db_configured}} ->
        {:noreply,
         assign(socket,
           notion_conn_status: :ok,
           notion_conn_message: "No data source configured; token valid"
         )}

      {{:ok, _user}, {:ok, _db}} ->
        {:noreply, assign(socket, notion_conn_status: :ok, notion_conn_message: nil)}

      {err1, err2} ->
        msg = format_conn_error(err1, err2)
        {:noreply, assign(socket, notion_conn_status: :error, notion_conn_message: msg)}
    end
  end

  # Auto-run Notion check for all statements on initial page load
  @impl true
  def handle_info(:auto_check_notion, socket) do
    rows = socket.assigns.statements || []

    case Notion.list_all_trademarks() do
      {:ok, trademark_set} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(rows, {%{}, 0, 0}, fn row, {acc, ec, mc} ->
            title = row.symbol <> "@" <> DateTime.to_iso8601(row.datetime)

            if MapSet.member?(trademark_set, title) do
              {Map.put(acc, row.id, :exists), ec + 1, mc}
            else
              {Map.put(acc, row.id, :missing), ec, mc + 1}
            end
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count,
           notion_conn_status: :ok,
           notion_conn_message: nil
         )}

      {:error, reason} ->
        row_statuses =
          rows
          |> Enum.reduce(%{}, fn row, acc -> Map.put(acc, row.id, :error) end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_conn_status: :error,
           notion_conn_message: "Failed to fetch Notion records: " <> inspect(reason)
         )}
    end
  end

  # Process one queued dump item at a time, spaced by 1s
  @impl true
  def handle_info(:process_next_dump, socket) do
    queue = socket.assigns.dump_queue

    case queue do
      [] ->
        # No more work
        now = System.monotonic_time(:millisecond)
        socket =
          socket
          |> assign(:dump_in_progress?, false)
          |> assign(:dump_current, nil)
          |> assign(:dump_finished_at_mono, socket.assigns.dump_finished_at_mono || now)
          |> assign(:dump_elapsed_ms,
            if socket.assigns.dump_started_at_mono do
              (socket.assigns.dump_finished_at_mono || now) - socket.assigns.dump_started_at_mono
            else
              0
            end
          )

        {:noreply, socket}

      [row | rest] ->
        # Mark current for UI
        socket = assign(socket, dump_current: row)

        # Perform existence check and maybe create
        {row_statuses, result_tag, next_queue, next_retry_counts, increment_processed?, next_delay_ms} =
          case Notion.exists_by_timestamp_and_ticker?(row.datetime, row.symbol) do
            {:ok, true} ->
              {
                Map.put(socket.assigns.row_statuses, row.id, :exists),
                :skipped_exists,
                rest,
                socket.assigns.dump_retry_counts,
                true,
                if(rest == [], do: 0, else: 1_000)
              }

            {:ok, false} ->
              case Notion.create_from_statement(row) do
                {:ok, _page} ->
                  {
                    Map.put(socket.assigns.row_statuses, row.id, :exists),
                    :created,
                    rest,
                    socket.assigns.dump_retry_counts,
                    true,
                    if(rest == [], do: 0, else: 1_000)
                  }

                {:error, _reason} ->
                  # Retry with linear backoff if under max retries
                  retries = Map.get(socket.assigns.dump_retry_counts, row.id, 0)

                  if retries < @dump_max_retries do
                    next_retries = Map.put(socket.assigns.dump_retry_counts, row.id, retries + 1)
                    backoff_ms = 1_000 * (retries + 1)

                    {
                      Map.put(socket.assigns.row_statuses, row.id, :retrying),
                      :retrying,
                      [row | rest],
                      next_retries,
                      false,
                      backoff_ms
                    }
                  else
                    {
                      Map.put(socket.assigns.row_statuses, row.id, :error),
                      :error,
                      rest,
                      socket.assigns.dump_retry_counts,
                      true,
                      if(rest == [], do: 0, else: 1_000)
                    }
                  end
              end

            {:error, _reason} ->
              {
                Map.put(socket.assigns.row_statuses, row.id, :error),
                :error,
                rest,
                socket.assigns.dump_retry_counts,
                true,
                if(rest == [], do: 0, else: 1_000)
              }
          end

        # Update results and progress
        dump_results = Map.put(socket.assigns.dump_results, row.id, result_tag)
        dump_processed = socket.assigns.dump_processed + if(increment_processed?, do: 1, else: 0)

        # Update elapsed time
        now = System.monotonic_time(:millisecond)
        elapsed_ms =
          if socket.assigns.dump_started_at_mono do
            now - socket.assigns.dump_started_at_mono
          else
            0
          end

        socket =
          socket
          |> assign(:row_statuses, row_statuses)
          |> assign(:dump_results, dump_results)
          |> assign(:dump_processed, dump_processed)
          |> assign(:dump_queue, next_queue)
          |> assign(:dump_retry_counts, next_retry_counts)
          |> assign(:dump_elapsed_ms, elapsed_ms)

        # Recompute exists/missing counts for currently selected rows
        {exists_count, missing_count} = recalc_selected_counts(socket)

        socket =
          socket
          |> assign(:notion_exists_count, exists_count)
          |> assign(:notion_missing_count, missing_count)

        # Schedule next item in 1 second
        Process.send_after(self(), :process_next_dump, next_delay_ms)

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <% total_count = length(@statements) %>
      <% filtered_rows = if @hide_exists? do
        Enum.reject(@statements, fn s -> Map.get(@row_statuses, s.id) == :exists end)
      else
        @statements
      end %>
      <% visible_count = length(filtered_rows) %>
      <% hidden_count = total_count - visible_count %>

      <div class="space-y-2">
        <!-- Row 1: Title and primary toggles -->
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <h1 class="text-xl font-semibold">Statement Dump</h1>

          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="toggle_select_all"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @all_selected?, do: "Clear All", else: "Select All"}
            </button>

            <button
              phx-click="toggle_hide_exists"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @hide_exists?, do: "Show All", else: "Hide Existing"}
            </button>

            <button
              phx-click="clear_row_statuses"
              class="inline-flex items-center px-3 py-2 rounded-md border border-red-300 text-sm bg-white text-red-600 hover:bg-red-50"
            >
              Clear Highlights
            </button>
          </div>
        </div>

        <!-- Row 2: Status badges on left, action buttons on right -->
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
              Selected: {MapSet.size(@selected_ids)}
            </span>

            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
              Visible: {visible_count}
            </span>

            <span :if={@hide_exists?} class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
              Hidden: {hidden_count}
            </span>

            <span
              :if={@notion_exists_count + @notion_missing_count > 0}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700"
            >
              Exists: {@notion_exists_count}
            </span>

            <span
              :if={@notion_exists_count + @notion_missing_count > 0}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700"
            >
              Missing: {@notion_missing_count}
            </span>

            <span
              :if={@notion_conn_status == :ok}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700"
            >
              Notion: Connected
            </span>

            <span
              :if={@notion_conn_status == :error}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700"
              title={@notion_conn_message}
            >
              Notion: Failed
            </span>
          </div>

          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="check_notion_connection"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
              phx-disable-with="Checking..."
              disabled={@dump_in_progress?}
            >
              Check Connection
            </button>

            <button
              phx-click="check_notion"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_ids) == 0 or @dump_in_progress?}
              phx-disable-with="Checking..."
            >
              Check Notion
            </button>

            <button
              phx-click="insert_missing_notion"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-green-600 text-white hover:bg-green-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_ids) == 0 or @dump_in_progress?}
              phx-disable-with="Starting..."
            >
              Insert Missing
            </button>
          </div>
        </div>

        <!-- Row 3: Dump progress bar and details -->
        <div :if={@dump_total > 0} class="w-full space-y-1">
          <% percent = if @dump_total > 0, do: Float.round(@dump_processed * 100.0 / @dump_total, 1), else: 0.0 %>
          <div class="flex items-center justify-between text-xs text-gray-600">
            <span>
              Dump progress: {@dump_processed}/{@dump_total} ({percent}%)
              {if @dump_in_progress?, do: "- in progress", else: "- completed"}
              · Time: {format_duration(@dump_elapsed_ms)}
            </span>
            <span :if={@dump_current} class="font-medium text-gray-700">
              Currently: {
                @dump_current.symbol <> " @ " <> DateTime.to_iso8601(@dump_current.datetime)
              }
            </span>
          </div>
          <div class="w-full bg-gray-200 rounded h-2 overflow-hidden">
            <div
              class="bg-green-500 h-2"
              style={"width: #{percent}%"}
            ></div>
          </div>
          <div :if={!@dump_in_progress?} class="text-xs text-gray-600">
            Total time: {format_duration(@dump_elapsed_ms)}
          </div>
        </div>
      </div>

      <ActivityStatementList.list
        id="statement-dump"
        title="All Statements"
        count={length(filtered_rows)}
        rows={filtered_rows}
        expanded={true}
        show_save_controls?={false}
        show_values?={true}
        selectable?={true}
        selected_ids={@selected_ids}
        all_selected?={@all_selected?}
        on_toggle_row_event="toggle_row"
        on_toggle_all_event="toggle_select_all"
        row_statuses={@row_statuses}
      />
    </div>
    """
  end

  # keep helpers after event handlers

  # keep helpers after event handlers

  defp format_conn_error(user_res, db_res) do
    ur =
      case user_res do
        {:ok, _} -> nil
        {:error, reason} -> "user: #{inspect(reason)}"
      end

    dr =
      case db_res do
        {:ok, _} -> nil
        {:error, reason} -> "db: #{inspect(reason)}"
      end

    [ur, dr]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  # Recompute exists/missing counts for currently selected rows
  defp recalc_selected_counts(socket) do
    selected_ids = socket.assigns.selected_ids
    statuses = socket.assigns.row_statuses || %{}

    {exists, missing} =
      Enum.reduce(selected_ids, {0, 0}, fn id, {e, m} ->
        case Map.get(statuses, id) do
          :exists -> {e + 1, m}
          :missing -> {e, m + 1}
          _ -> {e, m}
        end
      end)

    {exists, missing}
  end

  # Format milliseconds into H:MM:SS.mmm or M:SS.mmm (minimal hours)
  defp format_duration(ms) when is_integer(ms) and ms >= 0 do
    total_ms = ms
    hours = div(total_ms, 3_600_000)
    rem_after_h = rem(total_ms, 3_600_000)
    minutes = div(rem_after_h, 60_000)
    rem_after_m = rem(rem_after_h, 60_000)
    seconds = div(rem_after_m, 1_000)
    millis = rem(rem_after_m, 1_000)

    if hours > 0 do
      :io_lib.format("~B:~2..0B:~2..0B.~3..0B", [hours, minutes, seconds, millis])
      |> IO.iodata_to_binary()
    else
      :io_lib.format("~B:~2..0B.~3..0B", [minutes, seconds, millis])
      |> IO.iodata_to_binary()
    end
  end

  defp format_duration(_), do: "0:00.000"
end

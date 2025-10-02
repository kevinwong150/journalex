defmodule JournalexWeb.TradesDumpLive do
  use JournalexWeb, :live_view

  import Ecto.Query, only: [from: 2]
  alias Journalex.Repo
  alias Journalex.Trades.Trade
  alias Journalex.Activity
  alias JournalexWeb.AggregatedTradeList
  alias Journalex.Notion
  alias Journalex.Notion.Client, as: NotionClient

  @dump_max_retries 3

  @impl true
  def mount(_params, _session, socket) do
    trades = load_aggregated_trades()

    socket =
      socket
      |> assign(:trades, trades)
      |> assign(:selected_idx, MapSet.new())
      |> assign(:all_selected?, false)
      |> assign(:row_statuses, %{})
      |> assign(:notion_exists_count, 0)
      |> assign(:notion_missing_count, 0)
      |> assign(:notion_conn_status, :unknown)
      |> assign(:notion_conn_message, nil)
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
      |> assign(:dump_cancel_requested?, false)
      |> assign(:dump_timer_ref, nil)
      |> assign(:dump_report_text, nil)
      |> assign(:hide_exists?, false)

    if connected?(socket), do: send(self(), :auto_check_notion)

    {:ok, socket}
  end

  # Load aggregated trades, preferring the DB 'trades' table. If the DB has no
  # records yet, fall back to deriving close trades from parsed activity statements.
  defp load_aggregated_trades do
    db_rows =
      Repo.all(from t in Trade, order_by: [desc: t.datetime])

    case db_rows do
      rows when is_list(rows) and rows != [] ->
        rows

      _ ->
        Activity.list_all_activity_statements()
        |> Enum.filter(fn r -> Map.get(r, :position_action) == "close" end)
        |> Enum.map(&to_trade_row/1)
    end
  end

  defp to_trade_row(row) do
    %{
      datetime: Map.get(row, :datetime),
      ticker: Map.get(row, :symbol),
      aggregated_side: if(Map.get(row, :side) == "long", do: "SHORT", else: "LONG"),
      result: if(decimal_to_float(Map.get(row, :realized_pl)) > 0.0, do: "WIN", else: "LOSE"),
      realized_pl: Map.get(row, :realized_pl)
    }
  end

  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(n) when is_number(n), do: n * 1.0
  defp decimal_to_float(<<>>), do: 0.0

  defp decimal_to_float(bin) when is_binary(bin) do
    case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
      {n, _} -> n
      _ -> 0.0
    end
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_idx =
      socket.assigns.trades |> Enum.with_index() |> Enum.map(fn {_r, i} -> i end) |> MapSet.new()

    {selected_idx, all_selected?} =
      if socket.assigns.all_selected? do
        {MapSet.new(), false}
      else
        {all_idx, true}
      end

    {:noreply, assign(socket, selected_idx: selected_idx, all_selected?: all_selected?)}
  end

  @impl true
  def handle_event("toggle_row", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    selected = socket.assigns.selected_idx

    selected =
      if MapSet.member?(selected, idx) do
        MapSet.delete(selected, idx)
      else
        MapSet.put(selected, idx)
      end

    all_idx =
      socket.assigns.trades |> Enum.with_index() |> Enum.map(fn {_r, i} -> i end) |> MapSet.new()

    all_selected? = MapSet.equal?(selected, all_idx) and MapSet.size(all_idx) > 0

    {:noreply, assign(socket, selected_idx: selected, all_selected?: all_selected?)}
  end

  @impl true
  def handle_event("check_notion_connection", _params, socket) do
    user_res = NotionClient.me()

    notion_conf = Application.get_env(:journalex, Journalex.Notion, [])

    ds_id =
      Keyword.get(notion_conf, :trades_data_source_id) ||
        Keyword.get(notion_conf, :activity_statements_data_source_id)

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

  @impl true
  def handle_event("check_notion", _params, socket) do
    selected_idx = socket.assigns.selected_idx
    rows = socket.assigns.trades

    selected_pairs =
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {_r, i} -> MapSet.member?(selected_idx, i) end)

    case list_all_trade_trademarks() do
      {:ok, trademark_set} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(selected_pairs, {%{}, 0, 0}, fn {row, idx}, {acc, ec, mc} ->
            title = (row.ticker || row.symbol) <> "@" <> DateTime.to_iso8601(row.datetime)

            if MapSet.member?(trademark_set, title),
              do: {Map.put(acc, idx, :exists), ec + 1, mc},
              else: {Map.put(acc, idx, :missing), ec, mc + 1}
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count
         )}

      {:error, reason} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(selected_pairs, {%{}, 0, 0}, fn {_row, idx}, {acc, ec, mc} ->
            {Map.put(acc, idx, :error), ec, mc}
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count,
           notion_conn_status: :error,
           notion_conn_message: "Failed to fetch Notion records: " <> inspect(reason)
         )}
    end
  end

  @impl true
  def handle_event("insert_missing_notion", _params, socket) do
    if socket.assigns.dump_in_progress? do
      {:noreply, socket}
    else
      selected_idx = socket.assigns.selected_idx
      rows = socket.assigns.trades
      statuses = socket.assigns.row_statuses || %{}

      selected_pairs =
        rows
        |> Enum.with_index()
        |> Enum.filter(fn {_r, i} -> MapSet.member?(selected_idx, i) end)

      missing_pairs =
        selected_pairs
        |> Enum.filter(fn {_r, idx} -> Map.get(statuses, idx) == :missing end)

      queue = if missing_pairs == [], do: selected_pairs, else: missing_pairs

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
        |> assign(:dump_cancel_requested?, false)
        |> assign(:dump_report_text, nil)

      timer_ref = Process.send_after(self(), :process_next_dump, 0)
      {:noreply, assign(socket, :dump_timer_ref, timer_ref)}
    end
  end

  @impl true
  def handle_event("cancel_dump", _params, socket) do
    if socket.assigns.dump_in_progress? do
      if socket.assigns.dump_timer_ref, do: Process.cancel_timer(socket.assigns.dump_timer_ref)

      now = System.monotonic_time(:millisecond)

      socket =
        socket
        |> assign(:dump_cancel_requested?, true)
        |> assign(:dump_in_progress?, false)
        |> assign(:dump_queue, [])
        |> assign(:dump_current, nil)
        |> assign(:dump_timer_ref, nil)
        |> assign(:dump_finished_at_mono, now)
        |> assign(
          :dump_elapsed_ms,
          if socket.assigns.dump_started_at_mono do
            now - socket.assigns.dump_started_at_mono
          else
            0
          end
        )
        |> assign(
          :dump_report_text,
          build_dump_report(
            socket.assigns.dump_results,
            socket.assigns.dump_total,
            socket.assigns.dump_processed,
            0
          )
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_row_statuses", _params, socket) do
    {:noreply,
     assign(socket,
       row_statuses: %{},
       notion_exists_count: 0,
       notion_missing_count: 0
     )}
  end

  @impl true
  def handle_event("toggle_hide_exists", _params, socket) do
    {:noreply, assign(socket, hide_exists?: !socket.assigns.hide_exists?)}
  end

  @impl true
  def handle_info(:auto_check_notion, socket) do
    rows = socket.assigns.trades || []

    case list_all_trade_trademarks() do
      {:ok, trademark_set} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(Enum.with_index(rows), {%{}, 0, 0}, fn {row, i}, {acc, ec, mc} ->
            title = (row.ticker || row.symbol) <> "@" <> DateTime.to_iso8601(row.datetime)

            if MapSet.member?(trademark_set, title),
              do: {Map.put(acc, i, :exists), ec + 1, mc},
              else: {Map.put(acc, i, :missing), ec, mc + 1}
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
          |> Enum.with_index()
          |> Enum.reduce(%{}, fn {_row, i}, acc -> Map.put(acc, i, :error) end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_conn_status: :error,
           notion_conn_message: "Failed to fetch Notion records: " <> inspect(reason)
         )}
    end
  end

  @impl true
  def handle_info(:process_next_dump, socket) do
    if socket.assigns.dump_cancel_requested? do
      now = System.monotonic_time(:millisecond)

      socket =
        socket
        |> assign(:dump_in_progress?, false)
        |> assign(:dump_current, nil)
        |> assign(:dump_queue, [])
        |> assign(:dump_finished_at_mono, socket.assigns.dump_finished_at_mono || now)
        |> assign(
          :dump_elapsed_ms,
          if(socket.assigns.dump_started_at_mono,
            do:
              (socket.assigns.dump_finished_at_mono || now) -
                socket.assigns.dump_started_at_mono,
            else: 0
          )
        )
        |> assign(:dump_timer_ref, nil)
        |> assign(
          :dump_report_text,
          build_dump_report(
            socket.assigns.dump_results,
            socket.assigns.dump_total,
            socket.assigns.dump_processed,
            0
          )
        )

      {:noreply, socket}
    else
      queue = socket.assigns.dump_queue

      case queue do
        [] ->
          now = System.monotonic_time(:millisecond)

          socket =
            socket
            |> assign(:dump_in_progress?, false)
            |> assign(:dump_current, nil)
            |> assign(:dump_finished_at_mono, socket.assigns.dump_finished_at_mono || now)
            |> assign(
              :dump_elapsed_ms,
              if(socket.assigns.dump_started_at_mono,
                do:
                  (socket.assigns.dump_finished_at_mono || now) -
                    socket.assigns.dump_started_at_mono,
                else: 0
              )
            )
            |> assign(:dump_timer_ref, nil)
            |> assign(
              :dump_report_text,
              build_dump_report(
                socket.assigns.dump_results,
                socket.assigns.dump_total,
                socket.assigns.dump_processed,
                0
              )
            )

          {:noreply, socket}

        [{row, idx} | rest] ->
          socket = assign(socket, dump_current: row)

          {row_statuses, result_tag, next_queue, next_retry_counts, increment_processed?,
           next_delay_ms} =
            case Notion.exists_by_timestamp_and_ticker?(row.datetime, row.ticker || row.symbol,
                   data_source_id: trades_data_source_id()
                 ) do
              {:ok, true} ->
                {Map.put(socket.assigns.row_statuses, idx, :exists), :skipped_exists, rest,
                 socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000)}

              {:ok, false} ->
                case Notion.create_from_trade(row, data_source_id: trades_data_source_id()) do
                  {:ok, _page} ->
                    {Map.put(socket.assigns.row_statuses, idx, :exists), :created, rest,
                     socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000)}

                  {:error, _reason} ->
                    retries = Map.get(socket.assigns.dump_retry_counts, idx, 0)

                    if retries < @dump_max_retries do
                      next_retries = Map.put(socket.assigns.dump_retry_counts, idx, retries + 1)
                      backoff_ms = 1000 * (retries + 1)

                      {Map.put(socket.assigns.row_statuses, idx, :retrying), :retrying,
                       [{row, idx} | rest], next_retries, false, backoff_ms}
                    else
                      {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
                       socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000)}
                    end
                end

              {:error, _reason} ->
                {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
                 socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000)}
            end

          dump_results = Map.put(socket.assigns.dump_results, idx, result_tag)

          dump_processed =
            socket.assigns.dump_processed + if(increment_processed?, do: 1, else: 0)

          now = System.monotonic_time(:millisecond)

          elapsed_ms =
            if socket.assigns.dump_started_at_mono,
              do: now - socket.assigns.dump_started_at_mono,
              else: 0

          socket =
            socket
            |> assign(:row_statuses, row_statuses)
            |> assign(:dump_results, dump_results)
            |> assign(:dump_processed, dump_processed)
            |> assign(:dump_queue, next_queue)
            |> assign(:dump_retry_counts, next_retry_counts)
            |> assign(:dump_elapsed_ms, elapsed_ms)

          timer_ref = Process.send_after(self(), :process_next_dump, next_delay_ms)
          {:noreply, assign(socket, :dump_timer_ref, timer_ref)}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="space-y-2">
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <h1 class="text-xl font-semibold">Trades Dump</h1>

          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="toggle_select_all"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @all_selected?, do: "Clear All", else: "Select All"}
            </button>

            <button
              phx-click="clear_row_statuses"
              class="inline-flex items-center px-3 py-2 rounded-md border border-red-300 text-sm bg-white text-red-600 hover:bg-red-50"
            >
              Clear Highlights
            </button>

            <button
              phx-click="toggle_hide_exists"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @hide_exists?, do: "Show All", else: "Hide Existing"}
            </button>
          </div>
        </div>

        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
              Selected: {MapSet.size(@selected_idx)}
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
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress?}
              phx-disable-with="Checking..."
            >
              Check Notion
            </button>
            <button
              phx-click="insert_missing_notion"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-green-600 text-white hover:bg-green-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress?}
              phx-disable-with="Starting..."
            >
              Insert Missing
            </button>
            <button
              :if={@dump_in_progress?}
              phx-click="cancel_dump"
              class="inline-flex items-center px-3 py-2 rounded-md border border-red-300 text-sm bg-white text-red-600 hover:bg-red-50"
              phx-disable-with="Stopping..."
            >
              Stop
            </button>
          </div>
        </div>

        <div :if={@dump_total > 0} class="w-full space-y-1">
          <% percent =
            if @dump_total > 0, do: Float.round(@dump_processed * 100.0 / @dump_total, 1), else: 0.0 %>
          <div class="flex items-center justify-between text-xs text-gray-600">
            <span>
              Dump progress: {@dump_processed}/{@dump_total} ({percent}%) {if @dump_in_progress?,
                do: "- in progress",
                else: "- completed"} · Time: {format_duration(@dump_elapsed_ms)}
            </span>
            <span :if={@dump_current} class="font-medium text-gray-700">
              Currently: {(@dump_current.ticker || @dump_current.symbol) <>
                " @ " <> DateTime.to_iso8601(@dump_current.datetime)}
            </span>
          </div>

          <div class="w-full bg-gray-200 rounded h-2 overflow-hidden">
            <div class="bg-green-500 h-2" style={"width: #{percent}%"}></div>
          </div>

          <div :if={!@dump_in_progress?} class="text-xs text-gray-600">
            Total time: {format_duration(@dump_elapsed_ms)}
          </div>
          <div class="text-xs text-gray-700">
            <% values = Map.values(@dump_results) %>
            <% created = Enum.count(values, &(&1 == :created)) %>
            <% skipped = Enum.count(values, &(&1 == :skipped_exists)) %>
            <% errors = Enum.count(values, &(&1 == :error)) %>
            <% retrying = Enum.count(values, &(&1 == :retrying)) %>
            <% remaining = length(@dump_queue) %>

            <div class="flex items-center gap-2 flex-wrap">
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700">
                Created: {created}
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
                Skipped: {skipped}
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-700">
                Retrying: {retrying}
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">
                Errors: {errors}
              </span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
                Remaining: {remaining}
              </span>
            </div>
          </div>
        </div>
      </div>

      <% hidden_idx =
        if @hide_exists? do
          @row_statuses
          |> Enum.filter(fn {_i, st} -> st == :exists end)
          |> Enum.map(fn {i, _} -> i end)
          |> MapSet.new()
        else
          MapSet.new()
        end %>

      <AggregatedTradeList.aggregated_trade_list
        id="trades-dump"
        items={@trades}
        sortable={true}
        default_sort_by={:date}
        default_sort_dir={:desc}
        show_save_controls?={false}
        selectable?={true}
        selected_idx={@selected_idx}
        all_selected?={@all_selected?}
        on_toggle_row_event="toggle_row"
        on_toggle_all_event="toggle_select_all"
        row_statuses={@row_statuses}
        hidden_idx={hidden_idx}
      />
    </div>
    """
  end

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

    [ur, dr] |> Enum.reject(&is_nil/1) |> Enum.join("; ")
  end

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
      :io_lib.format("~B:~2..0B.~3..0B", [minutes, seconds, millis]) |> IO.iodata_to_binary()
    end
  end

  defp format_duration(_), do: "0:00.000"

  defp build_dump_report(results_map, _total, _processed, remaining) do
    values = Map.values(results_map)
    created = Enum.count(values, &(&1 == :created))
    skipped = Enum.count(values, &(&1 == :skipped_exists))
    errors = Enum.count(values, &(&1 == :error))
    retrying = Enum.count(values, &(&1 == :retrying))

    "Created " <>
      Integer.to_string(created) <>
      ", Skipped " <>
      Integer.to_string(skipped) <>
      ", Errors " <>
      Integer.to_string(errors) <>
      ", Retrying " <>
      Integer.to_string(retrying) <>
      ", Remaining " <> Integer.to_string(remaining)
  end

  # Fetch all titles for the trades database using trades_data_source_id
  defp list_all_trade_trademarks do
    case trades_data_source_id() do
      nil -> {:error, :missing_data_source_id}
      id -> Notion.list_all_trademarks(data_source_id: id)
    end
  end

  defp trades_data_source_id do
    conf = Application.get_env(:journalex, Journalex.Notion, [])

    Keyword.get(conf, :trades_data_source_id) ||
      Keyword.get(conf, :activity_statements_data_source_id) || Keyword.get(conf, :data_source_id)
  end
end

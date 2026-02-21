defmodule JournalexWeb.TradesDumpLive do
  use JournalexWeb, :live_view

  import Ecto.Query, only: [from: 2]
  alias Journalex.Repo
  alias Journalex.Trades.Trade
  alias Journalex.Activity
  alias JournalexWeb.AggregatedTradeList
  alias JournalexWeb.DumpProgress
  alias Journalex.Notion
  alias Journalex.Notion.Client, as: NotionClient
  alias Journalex.Notion.DataSources

  @dump_max_retries 3
  @supported_versions [1, 2]

  @impl true
  def mount(_params, _session, socket) do
    trades = load_aggregated_trades()

    socket =
      socket
      |> assign(:trades, trades)
      |> assign(:selected_idx, MapSet.new())
      |> assign(:all_selected?, false)
      |> assign(:row_statuses, %{})
      |> assign(:row_inconsistencies, %{})
      |> assign(:notion_exists_count, 0)
      |> assign(:notion_missing_count, 0)
      |> assign(:notion_conn_status, :unknown)
      |> assign(:notion_conn_message, nil)
      # Check (auto) progress state
      |> assign(:check_queue, [])
      |> assign(:check_total, 0)
      |> assign(:check_processed, 0)
      |> assign(:check_in_progress?, false)
      |> assign(:check_current, nil)
      |> assign(:check_started_at_mono, nil)
      |> assign(:check_finished_at_mono, nil)
      |> assign(:check_elapsed_ms, 0)
      |> assign(:check_timer_ref, nil)
      |> assign(:check_trademark_set, nil)
      |> assign(:check_id_map, nil)
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
      # Notion page ids per row title ("TICKER@ISO")
      |> assign(:notion_page_ids, %{})
      # Relation caches for TickerLink / DateLink
      |> assign(:ticker_id_cache, %{})
      |> assign(:date_id_cache, %{})
      # Update (bulk) progress state
      |> assign(:update_queue, [])
      |> assign(:update_total, 0)
      |> assign(:update_processed, 0)
      |> assign(:update_in_progress?, false)
      |> assign(:update_current, nil)
      |> assign(:update_started_at_mono, nil)
      |> assign(:update_finished_at_mono, nil)
      |> assign(:update_elapsed_ms, 0)
      |> assign(:update_timer_ref, nil)
      # Global metadata version for all forms — DB wins, app config is fallback
      |> assign(:global_metadata_version, Journalex.Settings.get_default_metadata_version())
      |> assign(:supported_versions, @supported_versions)

    if connected?(socket) && Journalex.Settings.get_auto_check_on_load(),
      do: send(self(), :auto_check_notion)

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

    # Refresh relation caches for TickerLink / DateLink
    {ticker_id_cache, ticker_cache_error} =
      case Notion.list_all_ticker_ids() do
        {:ok, map} -> {map, nil}
        {:error, reason} -> {socket.assigns.ticker_id_cache, "Ticker Details cache failed: #{inspect(reason)}"}
      end

    {date_id_cache, date_cache_error} =
      case Notion.list_all_date_ids() do
        {:ok, map} -> {map, nil}
        {:error, reason} -> {socket.assigns.date_id_cache, "Market Daily cache failed: #{inspect(reason)}"}
      end

    cache_warning =
      [ticker_cache_error, date_cache_error]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        msgs -> "Relation caches not loaded — " <> Enum.join(msgs, "; ")
      end

    case list_all_trade_trademarks_with_ids(socket.assigns.global_metadata_version) do
      {:ok, {trademark_set, id_map}} ->
        now = System.monotonic_time(:millisecond)

        socket =
          socket
          |> assign(:check_queue, selected_pairs)
          |> assign(:check_total, length(selected_pairs))
          |> assign(:check_processed, 0)
          |> assign(:check_in_progress?, true)
          |> assign(:check_current, nil)
          |> assign(:check_started_at_mono, now)
          |> assign(:check_finished_at_mono, nil)
          |> assign(:check_elapsed_ms, 0)
          |> assign(:check_trademark_set, trademark_set)
          |> assign(:check_id_map, id_map)
          |> assign(:notion_conn_status, :ok)
          |> assign(:notion_conn_message, nil)
          |> assign(:notion_page_ids, id_map)
          |> assign(:ticker_id_cache, ticker_id_cache)
          |> assign(:date_id_cache, date_id_cache)
          # reset counters for this run
          |> assign(:notion_exists_count, 0)
          |> assign(:notion_missing_count, 0)

        socket = if cache_warning, do: put_flash(socket, :error, cache_warning), else: socket

        timer_ref = Process.send_after(self(), :process_next_check, 0)
        {:noreply, assign(socket, :check_timer_ref, timer_ref)}

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
       row_inconsistencies: %{},
       notion_exists_count: 0,
       notion_missing_count: 0
     )}
  end

  @impl true
  def handle_event("update_row_in_notion", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    rows = socket.assigns.trades || []
    row = Enum.at(rows, idx)

    with true <- not is_nil(row),
         title <- (row.ticker || row.symbol) <> "@" <> DateTime.to_iso8601(row.datetime),
         page_id when is_binary(page_id) <- Map.get(socket.assigns.notion_page_ids || %{}, title),
         {:ok, _} <- Notion.update_trade_page(page_id, row) do
      # On success, re-check diffs for that row
      new_incons = Map.delete(socket.assigns.row_inconsistencies || %{}, idx)
      {:noreply, assign(socket, row_inconsistencies: new_incons)}
    else
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_all_selected", _params, socket) do
    selected = socket.assigns.selected_idx || MapSet.new()
    rows = socket.assigns.trades || []

    idx_with_diffs =
      socket.assigns.row_inconsistencies
      |> Map.keys()
      |> Enum.filter(&MapSet.member?(selected, &1))
      |> Enum.sort()

    queue = Enum.map(idx_with_diffs, fn idx -> {Enum.at(rows, idx), idx} end)

    socket =
      socket
      |> assign(:update_queue, queue)
      |> assign(:update_total, length(queue))
      |> assign(:update_processed, 0)
      |> assign(:update_in_progress?, true)
      |> assign(:update_current, nil)
      |> assign(:update_started_at_mono, System.monotonic_time(:millisecond))
      |> assign(:update_finished_at_mono, nil)
      |> assign(:update_elapsed_ms, 0)

    timer_ref = Process.send_after(self(), :process_next_update, 0)
    {:noreply, assign(socket, :update_timer_ref, timer_ref)}
  end

  @impl true
  def handle_event("toggle_hide_exists", _params, socket) do
    {:noreply, assign(socket, hide_exists?: !socket.assigns.hide_exists?)}
  end

  @impl true
  def handle_event("save_metadata", %{"index" => idx_str} = params, socket) do
    {idx, _} = Integer.parse(idx_str)
    version = socket.assigns.global_metadata_version

    trade = Enum.at(socket.assigns.trades, idx)

    if trade do
      # Build metadata from form params based on global version
      metadata_attrs = case version do
        1 -> build_v1_metadata_attrs(params)
        2 -> build_v2_metadata_attrs(params)
        _ -> %{}
      end

      # Preserve read-only rollup fields from existing metadata
      metadata_attrs = preserve_readonly_fields(metadata_attrs, trade.metadata)

      # Update trade in database with global version
      case Journalex.Trades.update_trade(trade, %{
        metadata: metadata_attrs,
        metadata_version: version
      }) do
        {:ok, updated_trade} ->
          # Update the specific trade in the list while preserving order
          trades =
            socket.assigns.trades
            |> Enum.with_index()
            |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

          socket =
            socket
            |> assign(:trades, trades)
            |> put_flash(:info, "Metadata saved as V#{version}")

          {:noreply, socket}

        {:error, changeset} ->
          socket = put_flash(socket, :error, "Failed to save metadata: #{inspect(changeset.errors)}")
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Trade not found")}
    end
  end

  @impl true
  def handle_event("reset_metadata", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    trade = Enum.at(socket.assigns.trades, idx)

    if trade do
      case Journalex.Trades.update_trade(trade, %{metadata: %{}, metadata_version: nil}) do
        {:ok, updated_trade} ->
          trades =
            socket.assigns.trades
            |> Enum.with_index()
            |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

          socket =
            socket
            |> assign(:trades, trades)
            |> put_flash(:info, "Metadata cleared")

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to reset metadata: #{inspect(changeset.errors)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Trade not found")}
    end
  end

  @impl true
  def handle_event("sync_metadata_from_notion", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    trade = Enum.at(socket.assigns.trades, idx)
    page_ids = socket.assigns.notion_page_ids || %{}

    title = if trade, do: row_title(trade), else: nil
    page_id = if title, do: Map.get(page_ids, title), else: nil

    cond do
      is_nil(trade) ->
        {:noreply, put_flash(socket, :error, "Trade not found")}

      is_nil(page_id) ->
        {:noreply,
         put_flash(socket, :error, "No Notion page found for this trade. Run 'Check Notion' first.")}

      true ->
        case Notion.sync_metadata_from_notion(trade.id, page_id) do
          {:ok, updated_trade} ->
            trades =
              socket.assigns.trades
              |> Enum.with_index()
              |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

            {:noreply,
             socket
             |> assign(:trades, trades)
             |> put_flash(:info, "Metadata synced from Notion")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Sync failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("change_global_version", %{"version" => version_str}, socket) do
    {version, _} = Integer.parse(version_str)

    if version in @supported_versions do
      {:noreply, assign(socket, :global_metadata_version, version)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:auto_check_notion, socket) do
    rows = socket.assigns.trades || []

    # Prefetch relation caches for TickerLink / DateLink
    {ticker_id_cache, ticker_cache_error} =
      case Notion.list_all_ticker_ids() do
        {:ok, map} -> {map, nil}
        {:error, reason} -> {%{}, "Ticker Details cache failed: #{inspect(reason)}"}
      end

    {date_id_cache, date_cache_error} =
      case Notion.list_all_date_ids() do
        {:ok, map} -> {map, nil}
        {:error, reason} -> {%{}, "Market Daily cache failed: #{inspect(reason)}"}
      end

    cache_warning =
      [ticker_cache_error, date_cache_error]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        msgs -> "Relation caches not loaded — " <> Enum.join(msgs, "; ")
      end

    case list_all_trade_trademarks_with_ids(socket.assigns.global_metadata_version) do
      {:ok, {trademark_set, id_map}} ->
        pairs = Enum.with_index(rows)

        now = System.monotonic_time(:millisecond)

        socket =
          socket
          |> assign(:check_queue, pairs)
          |> assign(:check_total, length(pairs))
          |> assign(:check_processed, 0)
          |> assign(:check_in_progress?, true)
          |> assign(:check_current, nil)
          |> assign(:check_started_at_mono, now)
          |> assign(:check_finished_at_mono, nil)
          |> assign(:check_elapsed_ms, 0)
          |> assign(:check_trademark_set, trademark_set)
          |> assign(:check_id_map, id_map)
          |> assign(:notion_conn_status, :ok)
          |> assign(:notion_conn_message, nil)
          |> assign(:notion_page_ids, id_map)
          |> assign(:ticker_id_cache, ticker_id_cache)
          |> assign(:date_id_cache, date_id_cache)
          # reset counters for this run
          |> assign(:notion_exists_count, 0)
          |> assign(:notion_missing_count, 0)

        socket = if cache_warning, do: put_flash(socket, :error, cache_warning), else: socket

        timer_ref = Process.send_after(self(), :process_next_check, 0)
        {:noreply, assign(socket, :check_timer_ref, timer_ref)}

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
  def handle_info(:process_next_check, socket) do
    queue = socket.assigns.check_queue || []

    case queue do
      [] ->
        now = System.monotonic_time(:millisecond)

        socket =
          socket
          |> assign(:check_in_progress?, false)
          |> assign(:check_current, nil)
          |> assign(:check_finished_at_mono, socket.assigns.check_finished_at_mono || now)
          |> assign(
            :check_elapsed_ms,
            if(socket.assigns.check_started_at_mono,
              do:
                (socket.assigns.check_finished_at_mono || now) -
                  socket.assigns.check_started_at_mono,
              else: 0
            )
          )
          |> assign(:check_timer_ref, nil)

        {:noreply, socket}

      [{row, idx} | rest] ->
        socket = assign(socket, check_current: row)

        trademark_set = socket.assigns.check_trademark_set || MapSet.new()
        id_map = socket.assigns.check_id_map || %{}

        title = row_title(row)
        status = if not is_nil(title) and MapSet.member?(trademark_set, title), do: :exists, else: :missing

        row_statuses = Map.put(socket.assigns.row_statuses || %{}, idx, status)

        {exists_count, missing_count} =
          case status do
            :exists -> {socket.assigns.notion_exists_count + 1, socket.assigns.notion_missing_count}
            _ -> {socket.assigns.notion_exists_count, socket.assigns.notion_missing_count + 1}
          end

        # If exists, fetch page and compute diffs; else leave inconsistencies as-is
        row_incons = socket.assigns.row_inconsistencies || %{}

        row_incons =
          case {status, Map.get(id_map, title)} do
            {:exists, page_id} when is_binary(page_id) ->
              case NotionClient.retrieve_page(page_id) do
                {:ok, page} ->
                  diffs = Notion.diff_trade_vs_page(row, page)
                  if map_size(diffs) > 0, do: Map.put(row_incons, idx, diffs), else: Map.delete(row_incons, idx)

                _ ->
                  row_incons
              end

            _ ->
              row_incons
          end

        now = System.monotonic_time(:millisecond)

        elapsed_ms =
          if socket.assigns.check_started_at_mono,
            do: now - socket.assigns.check_started_at_mono,
            else: 0

        socket =
          socket
          |> assign(:row_statuses, row_statuses)
          |> assign(:row_inconsistencies, row_incons)
          |> assign(:notion_exists_count, exists_count)
          |> assign(:notion_missing_count, missing_count)
          |> assign(:check_queue, rest)
          |> assign(:check_processed, socket.assigns.check_processed + 1)
          |> assign(:check_elapsed_ms, elapsed_ms)

        timer_ref = Process.send_after(self(), :process_next_check, 0)
        {:noreply, assign(socket, :check_timer_ref, timer_ref)}
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

          ticker = row.ticker || row.symbol
          date_key = trade_date_key(row)
          ticker_page_id = Map.get(socket.assigns.ticker_id_cache, ticker)
          date_page_id = Map.get(socket.assigns.date_id_cache, date_key)

          # Determine which Notion database to use for this row based on its metadata version
          row_version = Map.get(row, :metadata_version) || socket.assigns.global_metadata_version
          row_data_source_id = trades_data_source_id_for_version(row_version)

          # Fail immediately (no retry) if relation pages are missing
          missing_relations = build_missing_relations_message(ticker, ticker_page_id, date_key, date_page_id)

          {row_statuses, result_tag, next_queue, next_retry_counts, increment_processed?,
           next_delay_ms,
           new_id_map, flash_msg} =
            if missing_relations != nil do
              {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
               socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000),
               nil, missing_relations}
            else
              case Notion.exists_by_timestamp_and_ticker?(row.datetime, ticker,
                     data_source_id: row_data_source_id
                   ) do
                {:ok, true} ->
                  {Map.put(socket.assigns.row_statuses, idx, :exists), :skipped_exists, rest,
                   socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000), nil, nil}

                {:ok, false} ->
                  case Notion.create_from_trade(row,
                         data_source_id: row_data_source_id,
                         ticker_page_id: ticker_page_id,
                         date_page_id: date_page_id
                       ) do
                    {:ok, page} ->
                      # Capture created page id
                      iso = DateTime.to_iso8601(row.datetime)
                      title = ticker <> "@" <> iso
                      page_id = Map.get(page, "id")
                      id_map_delta = if is_binary(page_id), do: %{title => page_id}, else: nil

                      {Map.put(socket.assigns.row_statuses, idx, :exists), :created, rest,
                       socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000),
                       id_map_delta, nil}

                    {:error, _reason} ->
                      retries = Map.get(socket.assigns.dump_retry_counts, idx, 0)

                      if retries < @dump_max_retries do
                        next_retries = Map.put(socket.assigns.dump_retry_counts, idx, retries + 1)
                        backoff_ms = 1000 * (retries + 1)

                        {Map.put(socket.assigns.row_statuses, idx, :retrying), :retrying,
                         [{row, idx} | rest], next_retries, false, backoff_ms, nil, nil}
                      else
                        {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
                         socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000),
                         nil, nil}
                      end
                  end

                {:error, _reason} ->
                  {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
                   socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000), nil, nil}
              end
            end

          # Merge new page id into map if we just created a page
          notion_page_ids =
            case new_id_map do
              m when is_map(m) -> Map.merge(socket.assigns.notion_page_ids || %{}, m)
              _ -> socket.assigns.notion_page_ids || %{}
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
            |> assign(:notion_page_ids, notion_page_ids)

          # Show flash for missing relation pages
          socket =
            if flash_msg do
              put_flash(socket, :error, flash_msg)
            else
              socket
            end

          timer_ref = Process.send_after(self(), :process_next_dump, next_delay_ms)
          {:noreply, assign(socket, :dump_timer_ref, timer_ref)}
      end
    end
  end

  @impl true
  def handle_info(:process_next_update, socket) do
    queue = socket.assigns.update_queue

    case queue do
      [] ->
        now = System.monotonic_time(:millisecond)

        socket =
          socket
          |> assign(:update_in_progress?, false)
          |> assign(:update_current, nil)
          |> assign(:update_finished_at_mono, socket.assigns.update_finished_at_mono || now)
          |> assign(
            :update_elapsed_ms,
            if(socket.assigns.update_started_at_mono,
              do:
                (socket.assigns.update_finished_at_mono || now) -
                  socket.assigns.update_started_at_mono,
              else: 0
            )
          )
          |> assign(:update_timer_ref, nil)

        {:noreply, socket}

      [{row, idx} | rest] ->
        socket = assign(socket, update_current: row)

        title = row_title(row)
        page_id = Map.get(socket.assigns.notion_page_ids || %{}, title)

        {next_queue, increment_processed?} =
          case page_id do
            id when is_binary(id) ->
              case Notion.update_trade_page(id, row) do
                {:ok, _} -> {rest, true}
                _ -> {rest, true}
              end

            _ ->
              {rest, true}
          end

        # Recompute diffs for this row
        row_incons = socket.assigns.row_inconsistencies || %{}

        row_incons =
          case page_id do
            id when is_binary(id) ->
              case NotionClient.retrieve_page(id) do
                {:ok, page} ->
                  diffs = Notion.diff_trade_vs_page(row, page)

                  if map_size(diffs) > 0,
                    do: Map.put(row_incons, idx, diffs),
                    else: Map.delete(row_incons, idx)

                _ ->
                  row_incons
              end

            _ ->
              row_incons
          end

        now = System.monotonic_time(:millisecond)

        elapsed_ms =
          if socket.assigns.update_started_at_mono,
            do: now - socket.assigns.update_started_at_mono,
            else: 0

        socket =
          socket
          |> assign(:update_queue, next_queue)
          |> assign(
            :update_processed,
            socket.assigns.update_processed + if(increment_processed?, do: 1, else: 0)
          )
          |> assign(:update_elapsed_ms, elapsed_ms)
          |> assign(:row_inconsistencies, row_incons)

        timer_ref = Process.send_after(self(), :process_next_update, 0)
        {:noreply, assign(socket, :update_timer_ref, timer_ref)}
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

        <!-- Global Metadata Version Selector -->
        <div class="bg-white rounded-lg border border-gray-200 p-4 shadow-sm">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-semibold text-gray-700">Metadata Form Version</h3>
              <p class="text-xs text-gray-500 mt-1">Select which version form to display for all trades</p>
            </div>
            <div class="flex items-center gap-2">
              <%= for version <- @supported_versions do %>
                <button
                  type="button"
                  phx-click="change_global_version"
                  phx-value-version={version}
                  class={[
                    "px-4 py-2 text-sm font-medium rounded-md transition-colors",
                    if(@global_metadata_version == version,
                      do: "bg-blue-600 text-white shadow-sm",
                      else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
                    )
                  ]}
                >
                  V{version}
                </button>
              <% end %>
            </div>
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
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @check_in_progress?}
              phx-disable-with="Checking..."
            >
              Check Notion
            </button>
            <button
              phx-click="update_all_selected"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @update_in_progress? or @check_in_progress?}
              phx-disable-with="Updating..."
            >
              Update All
            </button>
            <button
              phx-click="insert_missing_notion"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-green-600 text-white hover:bg-green-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @check_in_progress?}
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

        <DumpProgress.progress
          :if={@check_total > 0}
          id="check-progress"
          title="Check progress"
          processed={@check_processed}
          total={@check_total}
          in_progress?={@check_in_progress?}
          elapsed_ms={@check_elapsed_ms}
          current_text={
            @check_current &&
              (@check_current.ticker || @check_current.symbol) <>
                " @ " <> DateTime.to_iso8601(@check_current.datetime)
          }
          metrics={%{remaining: length(@check_queue || [])}}
          labels={%{remaining: "Remaining"}}
        />

        <DumpProgress.progress
          :if={@dump_total > 0}
          id="insert-progress"
          title="Insert progress"
          processed={@dump_processed}
          total={@dump_total}
          in_progress?={@dump_in_progress?}
          elapsed_ms={@dump_elapsed_ms}
          current_text={
            @dump_current &&
              (@dump_current.ticker || @dump_current.symbol) <>
                " @ " <> DateTime.to_iso8601(@dump_current.datetime)
          }
          metrics={dump_metrics(@dump_results, @dump_queue)}
          labels={
            %{
              created: "Created",
              skipped: "Skipped",
              retrying: "Retrying",
              errors: "Errors",
              remaining: "Remaining"
            }
          }
        />

        <DumpProgress.progress
          :if={@update_total > 0}
          id="update-progress"
          title="Update progress"
          processed={@update_processed}
          total={@update_total}
          in_progress?={@update_in_progress?}
          elapsed_ms={@update_elapsed_ms}
          current_text={
            @update_current &&
              (@update_current.ticker || @update_current.symbol) <>
                " @ " <> DateTime.to_iso8601(@update_current.datetime)
          }
          metrics={%{remaining: length(@update_queue || [])}}
          labels={%{remaining: "Remaining"}}
        />
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
        page_ids_map={@notion_page_ids}
        show_page_id_column?={true}
        row_inconsistencies={@row_inconsistencies}
        show_inconsistency_column?={true}
        show_metadata_column?={true}
        on_save_metadata_event="save_metadata"
        on_reset_metadata_event="reset_metadata"
        on_sync_metadata_event="sync_metadata_from_notion"
        global_metadata_version={@global_metadata_version}
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

  # Build metrics map for DumpProgress component based on existing dump state
  defp dump_metrics(results_map, queue) when is_map(results_map) do
    values = Map.values(results_map)
    created = Enum.count(values, &(&1 == :created))
    skipped = Enum.count(values, &(&1 == :skipped_exists))
    errors = Enum.count(values, &(&1 == :error))
    retrying = Enum.count(values, &(&1 == :retrying))
    remaining = length(queue || [])

    %{
      created: created,
      skipped: skipped,
      retrying: retrying,
      errors: errors,
      remaining: remaining
    }
  end

  defp dump_metrics(_, _), do: %{}

  defp list_all_trade_trademarks_with_ids(version \\ nil) do
    id = trades_data_source_id_for_version(version)

    case id do
      nil ->
        {:error, :missing_data_source_id}

      id ->
        with {:ok, id_map} <- Notion.list_all_trademarks_with_ids(data_source_id: id) do
          {:ok, {Map.keys(id_map) |> MapSet.new(), id_map}}
        end
    end
  end

  # Returns the Notion data source ID for the given metadata version.
  # Uses DataSources.get_data_source_id/1 when a version is provided,
  # falling back to the legacy :trades_data_source_id config key.
  defp trades_data_source_id_for_version(nil) do
    conf = Application.get_env(:journalex, Journalex.Notion, [])

    Keyword.get(conf, :trades_data_source_id) ||
      Keyword.get(conf, :activity_statements_data_source_id) || Keyword.get(conf, :data_source_id)
  end

  defp trades_data_source_id_for_version(version) when is_integer(version) do
    DataSources.get_data_source_id(version) || trades_data_source_id_for_version(nil)
  end

  # --- Helpers for Notion checks ---
  defp row_title(%{datetime: dt} = row) do
    ticker = Map.get(row, :ticker) || Map.get(row, :symbol)
    iso = if is_struct(dt, DateTime), do: DateTime.to_iso8601(dt), else: nil
    if is_binary(ticker) and is_binary(iso), do: ticker <> "@" <> iso, else: nil
  end

  # Extract date key from trade row's datetime, matching Market Daily page title format ("2026-02-10")
  defp trade_date_key(%{datetime: %DateTime{} = dt}) do
    dt |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp trade_date_key(_), do: nil

  # Build a human-readable error message when TickerLink or DateLink relation pages are missing.
  # Returns nil if both are present.
  defp build_missing_relations_message(ticker, ticker_page_id, date_key, date_page_id) do
    missing =
      []
      |> then(fn acc ->
        if is_nil(ticker_page_id),
          do: ["Ticker page \"#{ticker}\" not found in Ticker Details database" | acc],
          else: acc
      end)
      |> then(fn acc ->
        if is_nil(date_page_id),
          do: ["Date page \"#{date_key}\" not found in Market Daily database" | acc],
          else: acc
      end)
      |> Enum.reverse()

    case missing do
      [] -> nil
      parts -> "Cannot insert: " <> Enum.join(parts, "; ")
    end
  end

  # --- Helpers for metadata form ---
  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> nil
    end
  end
  defp parse_integer(int) when is_integer(int), do: int

  defp parse_string(nil), do: nil
  defp parse_string(""), do: nil
  defp parse_string(str) when is_binary(str), do: String.trim(str)

  # Build V1 metadata attributes from form params
  defp build_v1_metadata_attrs(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      operation_mistake?: params["operation_mistake"] == "true",
      follow_setup?: params["follow_setup"] == "true",
      follow_stop_loss_management?: params["follow_stop_loss_management"] == "true",
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      unnecessary_trade?: params["unnecessary_trade"] == "true",
      close_time_comment: join_close_time_comments(params["close_time_comment"])
    }
  end

  # Build V2 metadata attributes from form params
  defp build_v2_metadata_attrs(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      order_type: parse_string(params["order_type"]),
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      add_size?: params["add_size"] == "true",
      adjusted_risk_reward?: params["adjusted_risk_reward"] == "true",
      align_with_trend?: params["align_with_trend"] == "true",
      better_risk_reward_ratio?: params["better_risk_reward_ratio"] == "true",
      big_picture?: params["big_picture"] == "true",
      earning_report?: params["earning_report"] == "true",
      follow_up_trial?: params["follow_up_trial"] == "true",
      good_lesson?: params["good_lesson"] == "true",
      hot_sector?: params["hot_sector"] == "true",
      momentum?: params["momentum"] == "true",
      news?: params["news"] == "true",
      normal_emotion?: params["normal_emotion"] == "true",
      operation_mistake?: params["operation_mistake"] == "true",
      overnight?: params["overnight"] == "true",
      overnight_in_purpose?: params["overnight_in_purpose"] == "true",
      skipped_position?: params["skipped_position"] == "true",
      close_time_comment: join_close_time_comments(params["close_time_comment"])
    }
  end

  # Join multi-checkbox close_time_comment values into comma-separated string
  defp join_close_time_comments(nil), do: nil
  defp join_close_time_comments([]), do: nil
  defp join_close_time_comments(list) when is_list(list) do
    joined = list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(", ")
    if joined == "", do: nil, else: joined
  end
  defp join_close_time_comments(str) when is_binary(str), do: parse_string(str)

  # Preserve read-only rollup fields (sector, cap_size) and auto-calculated timeslots from existing metadata
  defp preserve_readonly_fields(attrs, existing) when is_map(attrs) do
    existing = existing || %{}
    Enum.reduce([:sector, :cap_size, :entry_timeslot, :close_timeslot], attrs, fn field, acc ->
      val = Map.get(existing, field) || Map.get(existing, Atom.to_string(field))
      if val, do: Map.put(acc, field, val), else: acc
    end)
  end
  defp preserve_readonly_fields(attrs, _), do: attrs
end

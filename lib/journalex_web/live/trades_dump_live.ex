defmodule JournalexWeb.TradesDumpLive do
  use JournalexWeb, :live_view

  alias Journalex.Activity
  alias JournalexWeb.AggregatedTradeList
  alias JournalexWeb.DumpProgress
  alias JournalexWeb.QueueProcessor
  alias JournalexWeb.StatusBadge
  alias Journalex.Notion
  alias Journalex.Notion.DataSources
  alias Journalex.MetadataDrafts
  alias Journalex.WriteupDrafts
  alias Journalex.CombinedDrafts

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
      |> QueueProcessor.init_assigns(:check,
        check_trademark_set: nil,
        check_id_map: nil
      )
      # Dump queue/progress state
      |> QueueProcessor.init_assigns(:dump,
        dump_results: %{},
        dump_retry_counts: %{},
        dump_cancel_requested?: false,
        dump_report_text: nil,
        dump_errors: []
      )
      |> assign(:hide_exists?, false)
      # Notion page ids per row title ("TICKER@ISO")
      |> assign(:notion_page_ids, %{})
      # Relation caches for TickerLink / DateLink
      |> assign(:ticker_id_cache, %{})
      |> assign(:date_id_cache, %{})
      # Update (bulk) progress state
      |> QueueProcessor.init_assigns(:update)
      # Sync-from-Notion (bulk) progress state
      |> QueueProcessor.init_assigns(:sync, sync_results: %{})
      # Bulk writeup sync-from-Notion progress state
      |> QueueProcessor.init_assigns(:wsync, wsync_results: %{})
      # Global metadata version for all forms — DB wins, app config is fallback
      |> assign(:global_metadata_version, Journalex.Settings.get_default_metadata_version())
      |> assign(:supported_versions, @supported_versions)
      # Metadata drafts for quick-apply
      |> assign(:drafts, MetadataDrafts.list_drafts())
      # Writeup drafts for applying block content to trades
      |> assign(:writeup_drafts, WriteupDrafts.list_drafts())
      # Combined drafts for bind + push workflow
      |> assign(:combined_drafts, CombinedDrafts.list_drafts())
      |> assign(:bound_drafts_map, build_bound_drafts_map(CombinedDrafts.list_drafts()))
      # Writeup detail modal state
      |> assign(:writeup_modal_trade, nil)

    will_auto_check = connected?(socket) && Journalex.Settings.get_auto_check_on_load()
    socket = assign(socket, :auto_check_pending?, will_auto_check)

    if will_auto_check, do: send(self(), :auto_check_notion)

    {:ok, socket}
  end

  # Load aggregated trades, preferring the DB 'trades' table. If the DB has no
  # records yet, fall back to deriving close trades from parsed activity statements.
  defp load_aggregated_trades do
    db_rows = Journalex.Trades.list_all_trades()

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
    case Notion.check_connection() do
      {:ok, message} ->
        {:noreply, assign(socket, notion_conn_status: :ok, notion_conn_message: message)}

      {:error, message} ->
        {:noreply, assign(socket, notion_conn_status: :error, notion_conn_message: message)}
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
        socket =
          QueueProcessor.start_operation(socket, :check, selected_pairs, :process_next_check, fn s ->
            s
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
          end)

        socket = if cache_warning, do: put_toast(socket, :error, cache_warning), else: socket

        {:noreply, socket}

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

      {:noreply,
       QueueProcessor.start_operation(socket, :dump, queue, :process_next_dump, fn s ->
         s
         |> assign(:dump_results, %{})
         |> assign(:dump_retry_counts, %{})
         |> assign(:dump_cancel_requested?, false)
         |> assign(:dump_report_text, nil)
         |> assign(:dump_errors, [])
       end)}
    end
  end

  @impl true
  def handle_event("cancel_dump", _params, socket) do
    {:noreply, cancel_dump(socket)}
  end

  @impl true
  def handle_event("cancel_check", _params, socket) do
    {:noreply, QueueProcessor.cancel_operation(socket, :check)}
  end

  @impl true
  def handle_event("cancel_update", _params, socket) do
    {:noreply, QueueProcessor.cancel_operation(socket, :update)}
  end

  @impl true
  def handle_event("cancel_sync", _params, socket) do
    {:noreply, QueueProcessor.cancel_operation(socket, :sync)}
  end

  @impl true
  def handle_event("cancel_wsync", _params, socket) do
    {:noreply, QueueProcessor.cancel_operation(socket, :wsync)}
  end

  @impl true
  def handle_event("cancel_all", _params, socket) do
    socket =
      socket
      |> QueueProcessor.cancel_operation(:check)
      |> cancel_dump()
      |> QueueProcessor.cancel_operation(:update)
      |> QueueProcessor.cancel_operation(:sync)
      |> QueueProcessor.cancel_operation(:wsync)

    {:noreply, socket}
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

    {:noreply, QueueProcessor.start_operation(socket, :update, queue, :process_next_update)}
  end

  @impl true
  def handle_event("bulk_sync_from_notion", _params, socket) do
    selected = socket.assigns.selected_idx || MapSet.new()
    rows = socket.assigns.trades || []
    page_ids = socket.assigns.notion_page_ids || %{}

    queue =
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {row, idx} ->
        MapSet.member?(selected, idx) and is_binary(Map.get(page_ids, row_title(row)))
      end)

    if queue == [] do
      {:noreply,
       put_toast(
         socket,
         :error,
         "No selected trades with known Notion pages. Run \"Check Notion\" first."
       )}
    else
      {:noreply,
       QueueProcessor.start_operation(socket, :sync, queue, :process_next_sync, fn s ->
         assign(s, :sync_results, %{})
       end)}
    end
  end

  @impl true
  def handle_event("bulk_sync_writeup_from_notion", _params, socket) do
    selected = socket.assigns.selected_idx || MapSet.new()
    rows = socket.assigns.trades || []
    page_ids = socket.assigns.notion_page_ids || %{}

    queue =
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {row, idx} ->
        MapSet.member?(selected, idx) and is_binary(Map.get(page_ids, row_title(row)))
      end)

    if queue == [] do
      {:noreply,
       put_toast(
         socket,
         :error,
         "No selected trades with known Notion pages. Run \"Check Notion\" first."
       )}
    else
      {:noreply,
       QueueProcessor.start_operation(socket, :wsync, queue, :process_next_writeup_sync, fn s ->
         assign(s, :wsync_results, %{})
       end)}
    end
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
            |> put_toast(:info, "Metadata saved as V#{version}")

          {:noreply, socket}

        {:error, changeset} ->
          socket = put_toast(socket, :error, "Failed to save metadata: #{inspect(changeset.errors)}")
          {:noreply, socket}
      end
    else
      {:noreply, put_toast(socket, :error, "Trade not found")}
    end
  end

  @impl true
  def handle_event("apply_draft", %{"index" => idx_str, "draft-id" => draft_id_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {draft_id, _} = Integer.parse(draft_id_str)

    trade = Enum.at(socket.assigns.trades, idx)
    draft = MetadataDrafts.get_draft(draft_id)

    cond do
      is_nil(trade) ->
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(draft) ->
        {:noreply, put_toast(socket, :error, "Draft not found")}

      true ->
        metadata_attrs = draft.metadata || %{}
        # Preserve read-only rollup fields from existing trade metadata
        metadata_attrs = preserve_readonly_fields(metadata_attrs, trade.metadata)

        case Journalex.Trades.update_trade(trade, %{
          metadata: metadata_attrs,
          metadata_version: draft.metadata_version
        }) do
          {:ok, updated_trade} ->
            trades =
              socket.assigns.trades
              |> Enum.with_index()
              |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

            {:noreply,
             socket
             |> assign(:trades, trades)
             |> put_toast(:info, "Applied draft \"#{draft.name}\" to trade")}

          {:error, changeset} ->
            {:noreply, put_toast(socket, :error, "Failed to apply draft: #{inspect(changeset.errors)}")}
        end
    end
  end

  @impl true
  def handle_event("open_writeup_modal", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    trade = Enum.at(socket.assigns.trades, idx)

    if trade do
      {:noreply, assign(socket, :writeup_modal_trade, trade)}
    else
      {:noreply, put_toast(socket, :error, "Trade not found")}
    end
  end

  @impl true
  def handle_event("close_writeup_modal", _params, socket) do
    {:noreply, assign(socket, :writeup_modal_trade, nil)}
  end

  @impl true
  def handle_event("clear_writeup", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    trade = Enum.at(socket.assigns.trades, idx)

    case Journalex.Trades.update_trade(trade, %{writeup: []}) do
      {:ok, updated_trade} ->
        trades =
          socket.assigns.trades
          |> Enum.with_index()
          |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

        {:noreply, socket |> assign(:trades, trades) |> put_toast(:info, "Writeup cleared")}

      {:error, _} ->
        {:noreply, put_toast(socket, :error, "Failed to clear writeup")}
    end
  end

  @impl true
  def handle_event("apply_writeup_draft", %{"index" => idx_str, "draft-id" => draft_id_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {draft_id, _} = Integer.parse(draft_id_str)

    trade = Enum.at(socket.assigns.trades, idx)
    draft = WriteupDrafts.get_draft(draft_id)

    cond do
      is_nil(trade) ->
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(draft) ->
        {:noreply, put_toast(socket, :error, "Writeup draft not found")}

      true ->
        case Journalex.Trades.update_trade(trade, %{writeup: draft.blocks || []}) do
          {:ok, updated_trade} ->
            trades =
              socket.assigns.trades
              |> Enum.with_index()
              |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

            {:noreply,
             socket
             |> assign(:trades, trades)
             |> put_toast(:info, "Applied writeup \"#{draft.name}\" (#{length(draft.blocks || [])} blocks)")}

          {:error, changeset} ->
            {:noreply, put_toast(socket, :error, "Failed to apply writeup: #{inspect(changeset.errors)}")}
        end
    end
  end

  @impl true
  def handle_event("bind_combined_draft", %{"index" => idx_str, "draft-id" => draft_id_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {draft_id, _} = Integer.parse(draft_id_str)

    trade = Enum.at(socket.assigns.trades, idx)
    combined = CombinedDrafts.get_draft(draft_id)

    cond do
      is_nil(trade) ->
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(combined) ->
        {:noreply, put_toast(socket, :error, "Combined draft not found")}

      not is_nil(combined.trade_id) ->
        bound_trade = combined.trade
        bound_title = if bound_trade, do: "#{bound_trade.ticker}@#{DateTime.to_iso8601(bound_trade.datetime)}", else: "another trade"
        {:noreply, put_toast(socket, :error, "Draft \"#{combined.name}\" is already bound to #{bound_title}")}

      not is_nil(combined.applied_at) ->
        {:noreply, put_toast(socket, :error, "Draft \"#{combined.name}\" was already pushed to Notion")}

      not is_nil(Map.get(socket.assigns.bound_drafts_map, trade.id)) ->
        existing = Map.get(socket.assigns.bound_drafts_map, trade.id)
        {:noreply, put_toast(socket, :error, "Trade already has bound draft \"#{existing.name}\"")}

      true ->
        md = combined.metadata_draft
        wd = combined.writeup_draft

        # Build update attrs from whichever references exist
        attrs =
          %{}
          |> then(fn a ->
            if md do
              metadata_attrs = preserve_readonly_fields(md.metadata || %{}, trade.metadata)
              Map.merge(a, %{metadata: metadata_attrs, metadata_version: md.metadata_version})
            else
              a
            end
          end)
          |> then(fn a ->
            if wd, do: Map.put(a, :writeup, wd.blocks || []), else: a
          end)

        # Copy data to trade, then bind
        with {:ok, updated_trade} <- (if attrs == %{}, do: {:ok, trade}, else: Journalex.Trades.update_trade(trade, attrs)),
             {:ok, bound_draft} <- CombinedDrafts.bind_to_trade(combined, trade.id) do
          trades =
            socket.assigns.trades
            |> Enum.with_index()
            |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

          parts =
            [if(md, do: "metadata V#{md.metadata_version}"), if(wd, do: "#{length(wd.blocks || [])} writeup blocks")]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" + ")

          suffix = if parts != "", do: " (#{parts})", else: ""

          {:noreply,
           socket
           |> assign(:trades, trades)
           |> assign(:combined_drafts, CombinedDrafts.list_drafts())
           |> assign(:bound_drafts_map, Map.put(socket.assigns.bound_drafts_map, trade.id, bound_draft))
           |> put_toast(:info, "Bound \"#{combined.name}\" to #{trade.ticker}@#{DateTime.to_iso8601(trade.datetime)}#{suffix}")}
        else
          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, put_toast(socket, :error, "Failed to bind: #{inspect(cs.errors)}")}

          {:error, reason} ->
            {:noreply, put_toast(socket, :error, "Failed to bind: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("unbind_combined_draft", %{"index" => idx_str, "draft-id" => draft_id_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {draft_id, _} = Integer.parse(draft_id_str)

    trade = Enum.at(socket.assigns.trades, idx)
    combined = CombinedDrafts.get_draft(draft_id)

    cond do
      is_nil(trade) ->
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(combined) ->
        {:noreply, put_toast(socket, :error, "Combined draft not found")}

      not is_nil(combined.applied_at) ->
        {:noreply, put_toast(socket, :error, "Cannot unbind — already pushed to Notion")}

      true ->
        case CombinedDrafts.unbind_from_trade(combined) do
          {:ok, _unbound_draft} ->
            {:noreply,
             socket
             |> assign(:combined_drafts, CombinedDrafts.list_drafts())
             |> assign(:bound_drafts_map, Map.delete(socket.assigns.bound_drafts_map, trade.id))
             |> put_toast(:info, "Unbound \"#{combined.name}\"")}

          {:error, :already_pushed} ->
            {:noreply, put_toast(socket, :error, "Cannot unbind — already pushed to Notion")}

          {:error, reason} ->
            {:noreply, put_toast(socket, :error, "Failed to unbind: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("push_to_notion", %{"index" => idx_str, "draft-id" => draft_id_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {draft_id, _} = Integer.parse(draft_id_str)

    trade = Enum.at(socket.assigns.trades, idx)
    combined = CombinedDrafts.get_draft(draft_id)

    cond do
      is_nil(trade) ->
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(combined) ->
        {:noreply, put_toast(socket, :error, "Combined draft not found")}

      combined.trade_id != trade.id ->
        {:noreply, put_toast(socket, :error, "Draft is not bound to this trade")}

      is_nil(combined.notion_page_id) ->
        {:noreply, put_toast(socket, :error, "No placeholder — create one from Trade Drafts first")}

      not is_nil(combined.applied_at) ->
        {:noreply, put_toast(socket, :error, "Already pushed on #{Calendar.strftime(combined.applied_at, "%Y-%m-%d %H:%M")}")}

      socket.assigns.ticker_id_cache == %{} ->
        {:noreply, put_toast(socket, :error, "Run \"Check Notion\" first to populate relation caches")}

      true ->
        push_single_to_notion(socket, idx, trade, combined)
    end
  end

  @impl true
  def handle_event("create_placeholder_for_draft", %{"draft-id" => draft_id_str}, socket) do
    {draft_id, _} = Integer.parse(draft_id_str)
    combined = CombinedDrafts.get_draft(draft_id)

    cond do
      is_nil(combined) ->
        {:noreply, put_toast(socket, :error, "Combined draft not found")}

      not is_nil(combined.notion_page_id) ->
        {:noreply, put_toast(socket, :error, "Placeholder already exists")}

      true ->
        blocks = CombinedDrafts.placeholder_blocks()
        version = if combined.metadata_draft, do: combined.metadata_draft.metadata_version, else: socket.assigns.global_metadata_version

        case Notion.create_placeholder_page(combined.name, blocks, metadata_version: version) do
          {:ok, page} ->
            page_id = Map.get(page, "id")

            case CombinedDrafts.set_notion_page_id(combined, page_id) do
              {:ok, _} ->
                refreshed_drafts = CombinedDrafts.list_drafts()
                notion_url = "https://notion.so/" <> String.replace(page_id, "-", "")

                {:noreply,
                 socket
                 |> assign(:combined_drafts, refreshed_drafts)
                 |> assign(:bound_drafts_map, build_bound_drafts_map(refreshed_drafts))
                 |> put_toast(:info, "Placeholder created — #{notion_url}")}

              {:error, _} ->
                {:noreply, put_toast(socket, :error, "Page created but failed to save link")}
            end

          {:error, reason} ->
            {:noreply, put_toast(socket, :error, "Failed to create placeholder: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("bulk_push_to_notion", _params, socket) do
    if socket.assigns.ticker_id_cache == %{} do
      {:noreply, put_toast(socket, :error, "Run \"Check Notion\" first to populate relation caches")}
    else
      # Collect eligible trades: selected, have bound draft with notion_page_id, not yet pushed
      eligible =
        socket.assigns.selected_idx
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.map(fn idx ->
          trade = Enum.at(socket.assigns.trades, idx)
          draft = if trade, do: Map.get(socket.assigns.bound_drafts_map, trade.id)

          cond do
            is_nil(trade) -> nil
            is_nil(draft) -> nil
            is_nil(draft.notion_page_id) -> nil
            not is_nil(draft.applied_at) -> nil
            true -> {idx, trade, draft}
          end
        end)
        |> Enum.reject(&is_nil/1)

      if eligible == [] do
        {:noreply, put_toast(socket, :info, "No eligible trades to push (need bound draft with placeholder, not yet pushed)")}
      else
        {socket, pushed, skipped} =
          Enum.reduce(eligible, {socket, 0, 0}, fn {idx, trade, draft}, {sock, ok, skip} ->
            # Re-fetch draft to get latest state
            fresh_draft = CombinedDrafts.get_draft(draft.id)

            if fresh_draft && is_nil(fresh_draft.applied_at) do
              case push_single_to_notion_quiet(sock, idx, trade, fresh_draft) do
                {:ok, updated_socket} -> {updated_socket, ok + 1, skip}
                {:error, updated_socket} -> {updated_socket, ok, skip + 1}
              end
            else
              {sock, ok, skip + 1}
            end
          end)

        msg =
          cond do
            skipped == 0 -> "Pushed #{pushed} trade(s) to Notion"
            pushed == 0 -> "#{skipped} trade(s) skipped (missing relations or errors)"
            true -> "Pushed #{pushed} trade(s) to Notion. #{skipped} skipped."
          end

        {:noreply,
         socket
         |> assign(:combined_drafts, CombinedDrafts.list_drafts())
         |> assign(:bound_drafts_map, build_bound_drafts_map(CombinedDrafts.list_drafts()))
         |> assign(:selected_idx, MapSet.new())
         |> assign(:all_selected?, false)
         |> put_toast(:info, msg)}
      end
    end
  end

  # Push a single bound draft to Notion. Returns {:noreply, socket} for use in single-push handler.
  defp push_single_to_notion(socket, idx, trade, combined) do
    page_id = combined.notion_page_id
    ticker = trade.ticker || trade.symbol
    date_key = trade_date_key(trade)
    ticker_page_id = Map.get(socket.assigns.ticker_id_cache, ticker)
    date_page_id = Map.get(socket.assigns.date_id_cache, date_key)

    missing_relations = build_missing_relations_message(ticker, ticker_page_id, date_key, date_page_id)

    if missing_relations do
      {:noreply, put_toast(socket, :error, missing_relations)}
    else
      # Push reads from trade (source of truth after bind)
      case Notion.update_trade_page(page_id, trade,
             ticker_page_id: ticker_page_id,
             date_page_id: date_page_id
           ) do
        {:ok, _} ->
          writeup_result =
            if is_list(trade.writeup) && trade.writeup != [] do
              Notion.push_trade_writeup(page_id, trade.writeup)
            else
              {:ok, :no_writeup}
            end

          case writeup_result do
            {:ok, _} ->
              CombinedDrafts.mark_applied(combined)
              refreshed_drafts = CombinedDrafts.list_drafts()

              {:noreply,
               socket
               |> assign(:row_statuses, Map.put(socket.assigns.row_statuses, idx, :exists))
               |> assign(:combined_drafts, refreshed_drafts)
               |> assign(:bound_drafts_map, build_bound_drafts_map(refreshed_drafts))
               |> put_toast(:info, "Pushed \"#{combined.name}\" to Notion")}

            {:error, reason} ->
              {:noreply, put_toast(socket, :error, "Properties updated but writeup failed: #{inspect(reason)}")}
          end

        {:error, reason} ->
          {:noreply, put_toast(socket, :error, "Failed to push to Notion: #{inspect(reason)}")}
      end
    end
  end

  # Silent version for bulk push — returns {:ok, socket} or {:error, socket} without toasts.
  defp push_single_to_notion_quiet(socket, idx, trade, combined) do
    page_id = combined.notion_page_id
    ticker = trade.ticker || trade.symbol
    date_key = trade_date_key(trade)
    ticker_page_id = Map.get(socket.assigns.ticker_id_cache, ticker)
    date_page_id = Map.get(socket.assigns.date_id_cache, date_key)

    missing_relations = build_missing_relations_message(ticker, ticker_page_id, date_key, date_page_id)

    if missing_relations do
      {:error, socket}
    else
      case Notion.update_trade_page(page_id, trade,
             ticker_page_id: ticker_page_id,
             date_page_id: date_page_id
           ) do
        {:ok, _} ->
          writeup_result =
            if is_list(trade.writeup) && trade.writeup != [] do
              Notion.push_trade_writeup(page_id, trade.writeup)
            else
              {:ok, :no_writeup}
            end

          case writeup_result do
            {:ok, _} ->
              CombinedDrafts.mark_applied(combined)
              {:ok, assign(socket, :row_statuses, Map.put(socket.assigns.row_statuses, idx, :exists))}

            {:error, _} ->
              {:error, socket}
          end

        {:error, _} ->
          {:error, socket}
      end
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
            |> put_toast(:info, "Metadata cleared")

          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, put_toast(socket, :error, "Failed to reset metadata: #{inspect(changeset.errors)}")}
      end
    else
      {:noreply, put_toast(socket, :error, "Trade not found")}
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
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(page_id) ->
        {:noreply,
         put_toast(socket, :error, "No Notion page found for this trade. Run 'Check Notion' first.")}

      true ->
        case Notion.sync_metadata_from_notion(trade.id, page_id) do
          {:ok, updated_trade} ->
            trades =
              socket.assigns.trades
              |> Enum.with_index()
              |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

            row_incons = Map.delete(socket.assigns.row_inconsistencies || %{}, idx)

            {:noreply,
             socket
             |> assign(:trades, trades)
             |> assign(:row_inconsistencies, row_incons)
             |> put_toast(:info, "Metadata synced from Notion")}

          {:error, reason} ->
            {:noreply, put_toast(socket, :error, "Sync failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("sync_writeup_from_notion", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    trade = Enum.at(socket.assigns.trades, idx)
    page_ids = socket.assigns.notion_page_ids || %{}

    title = if trade, do: row_title(trade), else: nil
    page_id = if title, do: Map.get(page_ids, title), else: nil

    cond do
      is_nil(trade) ->
        {:noreply, put_toast(socket, :error, "Trade not found")}

      is_nil(page_id) ->
        {:noreply,
         put_toast(socket, :error, "No Notion page found for this trade. Run 'Check Notion' first.")}

      true ->
        case Notion.sync_writeup_from_notion(trade.id, page_id) do
          {:ok, updated_trade} ->
            trades =
              socket.assigns.trades
              |> Enum.with_index()
              |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

            {:noreply,
             socket
             |> assign(:trades, trades)
             |> put_toast(:info, "Writeup synced from Notion")}

          {:error, reason} ->
            {:noreply, put_toast(socket, :error, "Writeup sync failed: #{inspect(reason)}")}
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
    socket = assign(socket, :auto_check_pending?, false)
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

        socket =
          QueueProcessor.start_operation(socket, :check, pairs, :process_next_check, fn s ->
            s
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
          end)

        socket = if cache_warning, do: put_toast(socket, :error, cache_warning), else: socket

        {:noreply, socket}

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
        {:noreply, QueueProcessor.finish_operation(socket, :check)}

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
              recompute_row_diffs(row_incons, page_id, idx, row)

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
      socket =
        socket
        |> assign(:dump_queue, [])
        |> QueueProcessor.finish_operation(:dump, &dump_finish_extras/1)

      {:noreply, socket}
    else
      queue = socket.assigns.dump_queue

      case queue do
        [] ->
          {:noreply, QueueProcessor.finish_operation(socket, :dump, &dump_finish_extras/1)}

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
           new_id_map, flash_msg, error_entry} =
            if missing_relations != nil do
              {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
               socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000),
               nil, missing_relations, {ticker <> "@" <> DateTime.to_iso8601(row.datetime), missing_relations}}
            else
              case Notion.exists_by_timestamp_and_ticker?(row.datetime, ticker,
                     data_source_id: row_data_source_id
                   ) do
                {:ok, true} ->
                  {Map.put(socket.assigns.row_statuses, idx, :exists), :skipped_exists, rest,
                   socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000), nil, nil, nil}

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

                      # Push writeup blocks if the trade has them
                      writeup_flash =
                        if is_binary(page_id) && is_list(row.writeup) && row.writeup != [] do
                          case Notion.push_trade_writeup(page_id, row.writeup) do
                            {:ok, _} -> nil
                            {:error, reason} -> "Writeup blocks failed for #{title}: #{inspect(reason)}"
                          end
                        else
                          nil
                        end

                      {Map.put(socket.assigns.row_statuses, idx, :exists), :created, rest,
                       socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000),
                       id_map_delta, writeup_flash, nil}

                    {:error, reason} ->
                      retries = Map.get(socket.assigns.dump_retry_counts, idx, 0)

                      if retries < @dump_max_retries do
                        next_retries = Map.put(socket.assigns.dump_retry_counts, idx, retries + 1)
                        backoff_ms = 1000 * (retries + 1)

                        {Map.put(socket.assigns.row_statuses, idx, :retrying), :retrying,
                         [{row, idx} | rest], next_retries, false, backoff_ms, nil, nil, nil}
                      else
                        label = ticker <> "@" <> DateTime.to_iso8601(row.datetime)
                        {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
                         socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000),
                         nil, nil, {label, format_notion_error(reason)}}
                      end
                  end

                {:error, reason} ->
                  label = ticker <> "@" <> DateTime.to_iso8601(row.datetime)
                  {Map.put(socket.assigns.row_statuses, idx, :error), :error, rest,
                   socket.assigns.dump_retry_counts, true, if(rest == [], do: 0, else: 1000), nil, nil,
                   {label, format_notion_error(reason)}}
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

          socket =
            if error_entry do
              {label, reason_str} = error_entry
              assign(socket, :dump_errors, socket.assigns.dump_errors ++ [%{label: label, reason: reason_str}])
            else
              socket
            end

          # Show flash for missing relation pages
          socket =
            if flash_msg do
              put_toast(socket, :error, flash_msg)
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
        {:noreply, QueueProcessor.finish_operation(socket, :update)}

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
        row_incons = recompute_row_diffs(row_incons, page_id, idx, row)

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
  def handle_info(:process_next_sync, socket) do
    process_sync_step(socket, :sync, &Notion.sync_metadata_from_notion/2, :process_next_sync)
  end

  @impl true
  def handle_info(:process_next_writeup_sync, socket) do
    process_sync_step(socket, :wsync, &Notion.sync_writeup_from_notion/2, :process_next_writeup_sync)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="space-y-2">
        <%!-- A. Header Row: Title + Version pills + Status badges --%>
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex items-center gap-3">
            <h1 class="text-xl font-semibold">Trades Dump</h1>
            <div class="flex items-center rounded-md border border-gray-200 overflow-hidden">
              <%= for version <- @supported_versions do %>
                <button
                  type="button"
                  phx-click="change_global_version"
                  phx-value-version={version}
                  class={[
                    "px-3 py-1 text-xs font-medium transition-colors",
                    if(@global_metadata_version == version,
                      do: "bg-blue-600 text-white",
                      else: "bg-white text-gray-600 hover:bg-gray-50"
                    )
                  ]}
                >
                  V{version}
                </button>
              <% end %>
            </div>
          </div>

          <div class="flex items-center gap-2 flex-wrap">
            <StatusBadge.status_badge color={:gray} label="Selected" value={MapSet.size(@selected_idx)} />
            <StatusBadge.status_badge
              :if={@notion_exists_count + @notion_missing_count > 0}
              color={:green}
              label="Exists"
              value={@notion_exists_count}
            />
            <StatusBadge.status_badge
              :if={@notion_exists_count + @notion_missing_count > 0}
              color={:red}
              label="Missing"
              value={@notion_missing_count}
            />
            <StatusBadge.status_badge
              :if={@notion_conn_status == :ok}
              color={:green}
              label="Notion"
              value="Connected"
            />
            <StatusBadge.status_badge
              :if={@notion_conn_status == :error}
              color={:red}
              label="Notion"
              value="Failed"
              title={@notion_conn_message}
            />
            <StatusBadge.status_badge
              :if={@auto_check_pending?}
              color={:blue}
              label="Notion"
              value="Checking…"
              spinner?={true}
            />
          </div>
        </div>

        <%!-- B. Toolbar Card: grouped action buttons in 2 rows --%>
        <div class="bg-white rounded-lg border border-gray-200 px-4 py-3 shadow-sm space-y-2">
          <%!-- Row 1: View & Notion --%>
          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="toggle_select_all"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @all_selected?, do: "Clear All", else: "Select All"}
            </button>
            <button
              phx-click="clear_row_statuses"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-red-300 text-sm bg-white text-red-600 hover:bg-red-50"
            >
              Clear Highlights
            </button>
            <button
              phx-click="toggle_hide_exists"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @hide_exists?, do: "Show All", else: "Hide Existing"}
            </button>

            <div class="w-px h-5 bg-gray-200 mx-1"></div>

            <button
              phx-click="check_notion_connection"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
              phx-disable-with="Checking..."
              disabled={@dump_in_progress?}
            >
              Check Connection
            </button>
            <button
              phx-click="check_notion"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-transparent text-sm bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @check_in_progress?}
              phx-disable-with="Checking..."
            >
              Check Notion
            </button>
            <span class="text-xs text-gray-400 ml-1">Bulk actions apply to selected rows</span>
          </div>

          <%!-- Row 2: Actions & Control --%>
          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="update_all_selected"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-transparent text-sm bg-indigo-600 text-white hover:bg-indigo-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @update_in_progress? or @check_in_progress?}
              phx-disable-with="Updating..."
            >
              Update All
            </button>
            <button
              phx-click="bulk_sync_from_notion"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-transparent text-sm bg-teal-600 text-white hover:bg-teal-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @update_in_progress? or @check_in_progress? or @sync_in_progress?}
              phx-disable-with="Starting..."
            >
              Sync Metadata
            </button>
            <button
              phx-click="bulk_sync_writeup_from_notion"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-transparent text-sm bg-violet-600 text-white hover:bg-violet-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @update_in_progress? or @check_in_progress? or @wsync_in_progress?}
              phx-disable-with="Starting..."
            >
              Sync Writeup
            </button>

            <div class="w-px h-5 bg-gray-200 mx-1"></div>

            <button
              phx-click="bulk_push_to_notion"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-transparent text-sm bg-sky-600 text-white hover:bg-sky-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @check_in_progress?}
              phx-disable-with="Pushing..."
            >
              Push Bound
            </button>
            <button
              phx-click="insert_missing_notion"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-transparent text-sm bg-green-600 text-white hover:bg-green-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_idx) == 0 or @dump_in_progress? or @check_in_progress?}
              phx-disable-with="Starting..."
            >
              Insert Missing
            </button>

            <div
              :if={@check_in_progress? or @dump_in_progress? or @update_in_progress? or @sync_in_progress? or @wsync_in_progress?}
              class="w-px h-5 bg-gray-200 mx-1"
            >
            </div>
            <button
              :if={@check_in_progress? or @dump_in_progress? or @update_in_progress? or @sync_in_progress? or @wsync_in_progress?}
              phx-click="cancel_all"
              class="inline-flex items-center px-3 py-1.5 rounded-md border border-red-300 text-sm bg-white text-red-600 hover:bg-red-50"
              phx-disable-with="Stopping..."
            >
              Stop
            </button>
          </div>
        </div>

        <%!-- C. Progress Container --%>
        <div
          :if={@check_total > 0 or @dump_total > 0 or @update_total > 0 or @sync_total > 0 or @wsync_total > 0}
          class="rounded-lg border border-gray-100 bg-gray-50 p-3 space-y-2"
        >
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

          <details
            :if={length(@dump_errors) > 0}
            class="rounded-lg border border-red-200 bg-red-50 text-sm"
          >
            <summary class="cursor-pointer select-none px-4 py-2 font-medium text-red-700">
              Insert errors ({length(@dump_errors)}) — click to expand
            </summary>
            <div class="px-4 pb-3 pt-1 space-y-1">
              <div :for={entry <- @dump_errors} class="flex gap-2 text-xs text-red-800 font-mono">
                <span class="font-semibold shrink-0">{entry.label}:</span>
                <span class="break-all">{entry.reason}</span>
              </div>
            </div>
          </details>

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

          <DumpProgress.progress
            :if={@sync_total > 0}
            id="sync-progress"
            title="Sync from Notion progress"
            processed={@sync_processed}
            total={@sync_total}
            in_progress?={@sync_in_progress?}
            elapsed_ms={@sync_elapsed_ms}
            current_text={
              @sync_current &&
                (@sync_current.ticker || @sync_current.symbol) <>
                  " @ " <> DateTime.to_iso8601(@sync_current.datetime)
            }
            metrics={%{
              synced: Enum.count(@sync_results, fn {_, v} -> v == :synced end),
              errors: Enum.count(@sync_results, fn {_, v} -> v == :error end),
              remaining: length(@sync_queue || [])
            }}
            labels={%{synced: "Synced", errors: "Errors", remaining: "Remaining"}}
          />

          <DumpProgress.progress
            :if={@wsync_total > 0}
            id="wsync-progress"
            title="Sync Writeup from Notion progress"
            processed={@wsync_processed}
            total={@wsync_total}
            in_progress?={@wsync_in_progress?}
            elapsed_ms={@wsync_elapsed_ms}
            current_text={
              @wsync_current &&
                (@wsync_current.ticker || @wsync_current.symbol) <>
                  " @ " <> DateTime.to_iso8601(@wsync_current.datetime)
            }
            metrics={%{
              synced: Enum.count(@wsync_results, fn {_, v} -> v == :synced end),
              errors: Enum.count(@wsync_results, fn {_, v} -> v == :error end),
              remaining: length(@wsync_queue || [])
            }}
            labels={%{synced: "Synced", errors: "Errors", remaining: "Remaining"}}
          />
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
        page_ids_map={@notion_page_ids}
        show_page_id_column?={true}
        row_inconsistencies={@row_inconsistencies}
        show_inconsistency_column?={true}
        show_metadata_column?={true}
        on_save_metadata_event="save_metadata"
        on_reset_metadata_event="reset_metadata"
        on_sync_metadata_event="sync_metadata_from_notion"
        global_metadata_version={@global_metadata_version}
        drafts={Enum.filter(@drafts, & &1.metadata_version == @global_metadata_version)}
        on_apply_draft_event="apply_draft"
        writeup_drafts={@writeup_drafts}
        on_apply_writeup_draft_event="apply_writeup_draft"
        combined_drafts={@combined_drafts}
        bound_drafts_map={@bound_drafts_map}
        on_bind_combined_draft_event="bind_combined_draft"
        on_unbind_combined_draft_event="unbind_combined_draft"
        on_push_to_notion_event="push_to_notion"
        on_create_placeholder_event="create_placeholder_for_draft"
        on_clear_writeup_event="clear_writeup"
        on_sync_writeup_event="sync_writeup_from_notion"
        on_open_writeup_modal_event="open_writeup_modal"
      />

      <%!-- Writeup detail modal (single shared instance) --%>
      <.modal
        :if={@writeup_modal_trade}
        id="writeup-detail-modal"
        show
        on_cancel={JS.push("close_writeup_modal")}
      >
        <% wt = @writeup_modal_trade %>
        <% wblocks = wt.writeup || [] %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-base font-semibold text-slate-800">
                {(wt.ticker || wt.symbol) <> "@" <> DateTime.to_iso8601(wt.datetime)}
              </h3>
              <p class="text-xs text-slate-500 mt-0.5">Full writeup</p>
            </div>
            <span :if={wblocks != []} class="text-xs font-medium text-violet-600 bg-violet-100 px-2 py-0.5 rounded-full">
              {length(wblocks)} blocks
            </span>
          </div>

          <div :if={wblocks == []} class="rounded-lg border border-dashed border-slate-300 p-4 text-sm text-slate-500">
            No writeup content.
          </div>

          <div :if={wblocks != []} class="space-y-1">
            <%= for block <- wblocks do %>
              <% btype = block["type"] || block[:type] || "paragraph" %>
              <% btext = block["text"] || block[:text] || "" %>
              <% children = block["children"] || block[:children] || [] %>
              <%= if btype == "toggle" do %>
                <div class="rounded-md border border-violet-100 bg-violet-50/50 p-2">
                  <div class="flex items-baseline gap-1.5">
                    <span class="shrink-0 text-xs text-violet-400">▸</span>
                    <span class={["text-sm font-medium text-violet-800", if(btext == "", do: "text-slate-300 italic", else: "")]}>
                      {if btext == "", do: "(empty)", else: btext}
                    </span>
                  </div>
                  <div :if={children != []} class="ml-4 mt-1 border-l-2 border-violet-200 pl-3 space-y-0.5">
                    <%= for child <- children do %>
                      <% ctext = child["text"] || child[:text] || "" %>
                      <p class={["text-sm text-slate-700", if(ctext == "", do: "text-slate-300 italic", else: "")]}>
                        {if ctext == "", do: "(empty)", else: ctext}
                      </p>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <p class={["text-sm text-slate-700 pl-5", if(btext == "", do: "text-slate-300 italic", else: "")]}>
                  {if btext == "", do: "(empty)", else: btext}
                </p>
              <% end %>
            <% end %>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  defp format_notion_error({:http_error, status, %{"code" => code, "message" => msg}}),
    do: "HTTP #{status} — #{code}: #{msg}"

  defp format_notion_error({:http_error, status, body}),
    do: "HTTP #{status} — #{inspect(body)}"

  defp format_notion_error(:missing_notion_api_token),
    do: "Notion API token is not configured"

  defp format_notion_error(reason),
    do: inspect(reason)

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

  defp dump_finish_extras(socket) do
    assign(socket, :dump_report_text,
      build_dump_report(
        socket.assigns.dump_results,
        socket.assigns.dump_total,
        socket.assigns.dump_processed,
        0
      )
    )
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

  defp list_all_trade_trademarks_with_ids(version) do
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
  # parse_integer/1 removed — unused. Recoverable from git.

  defp parse_string(nil), do: nil
  defp parse_string(""), do: nil
  defp parse_string(str) when is_binary(str), do: String.trim(str)

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {d, ""} -> d
      _       -> nil
    end
  end

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
      slipped_position?: params["slipped_position"] == "true",
      choppychart?: params["choppychart"] == "true",
      close_trade_remorse?: params["close_trade_remorse"] == "true",
      no_luck?: params["no_luck"] == "true",
      no_risk?: params["no_risk"] == "true",
      clear_liquidity_grab?: params["clear_liquidity_grab"] == "true",
      entry_after_liquidity_grab?: params["entry_after_liquidity_grab"] == "true",
      instant_lose?: params["instant_lose"] == "true",
      too_tight_stop_loss?: params["too_tight_stop_loss"] == "true",
      affected_by_other_trade?: params["affected_by_other_trade"] == "true",
      mid_range?: params["mid_range"] == "true",
      fully_wrong_direction?: params["fully_wrong_direction"] == "true",
      initial_risk_reward_ratio: parse_decimal(params["initial_risk_reward_ratio"]),
      best_risk_reward_ratio: (if params["best_rr_enabled"] == "true", do: parse_decimal(params["best_risk_reward_ratio"]), else: Decimal.new("0")),
      size: parse_decimal(params["size"]),
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

  # Build %{trade_id => draft} map from list of combined drafts for quick lookup
  defp build_bound_drafts_map(drafts) do
    drafts
    |> Enum.filter(& &1.trade_id)
    |> Map.new(& {&1.trade_id, &1})
  end

  # --- Operation lifecycle helpers (finish + cancel) ---

  defp recompute_row_diffs(row_incons, page_id, idx, row) when is_binary(page_id) do
    case Notion.retrieve_and_diff(page_id, row) do
      {:ok, diffs} when map_size(diffs) > 0 -> Map.put(row_incons, idx, diffs)
      {:ok, _} -> Map.delete(row_incons, idx)
      {:error, _} -> row_incons
    end
  end

  defp recompute_row_diffs(row_incons, _page_id, _idx, _row), do: row_incons

  defp process_sync_step(socket, prefix, sync_fn, message) do
    queue = socket.assigns[:"#{prefix}_queue"]

    case queue do
      [] ->
        {:noreply, QueueProcessor.finish_operation(socket, prefix)}

      [{row, idx} | rest] ->
        socket = assign(socket, :"#{prefix}_current", row)
        page_ids = socket.assigns.notion_page_ids || %{}
        page_id = Map.get(page_ids, row_title(row))

        {updated_trades, result_tag} =
          case {Map.get(row, :id), page_id} do
            {id, pid} when not is_nil(id) and is_binary(pid) ->
              case sync_fn.(id, pid) do
                {:ok, updated_trade} ->
                  trades =
                    socket.assigns.trades
                    |> Enum.with_index()
                    |> Enum.map(fn {t, i} -> if i == idx, do: updated_trade, else: t end)

                  {trades, :synced}

                {:error, _} ->
                  {socket.assigns.trades, :error}
              end

            _ ->
              {socket.assigns.trades, :skipped}
          end

        now = System.monotonic_time(:millisecond)

        elapsed_ms =
          if socket.assigns[:"#{prefix}_started_at_mono"],
            do: now - socket.assigns[:"#{prefix}_started_at_mono"],
            else: 0

        results = Map.put(socket.assigns[:"#{prefix}_results"] || %{}, idx, result_tag)

        row_incons =
          if prefix == :sync and result_tag == :synced,
            do: Map.delete(socket.assigns.row_inconsistencies || %{}, idx),
            else: socket.assigns.row_inconsistencies || %{}

        socket =
          socket
          |> assign(:trades, updated_trades)
          |> assign(:"#{prefix}_queue", rest)
          |> assign(:"#{prefix}_processed", socket.assigns[:"#{prefix}_processed"] + 1)
          |> assign(:"#{prefix}_results", results)
          |> assign(:"#{prefix}_elapsed_ms", elapsed_ms)
          |> assign(:row_inconsistencies, row_incons)

        timer_ref = Process.send_after(self(), message, 0)
        {:noreply, assign(socket, :"#{prefix}_timer_ref", timer_ref)}
    end
  end

  defp cancel_dump(socket) do
    QueueProcessor.cancel_operation(socket, :dump, fn socket ->
      socket
      |> assign(:dump_cancel_requested?, true)
      |> assign(
        :dump_report_text,
        build_dump_report(
          socket.assigns.dump_results,
          socket.assigns.dump_total,
          socket.assigns.dump_processed,
          0
        )
      )
    end)
  end
end

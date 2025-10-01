defmodule JournalexWeb.ActivityStatementLive do
  use JournalexWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias Journalex.ActivityStatementParser
  alias Journalex.Activity
  alias JournalexWeb.ActivityStatementSummary
  alias JournalexWeb.ActivityStatementList

  @impl true
  def mount(_params, _session, socket) do
    trades = load_all_trades() |> Activity.dedupe_by_datetime_symbol()
    # annotate each row with existence flag
    exists_flags = Activity.rows_exist_flags(trades)

    annotated_trades =
      trades
      |> Enum.with_index()
      |> Enum.map(fn {row, idx} -> Map.put(row, :exists, Enum.at(exists_flags, idx)) end)

    # Build day list and selection map (default ON)
    days = unique_trade_dates(annotated_trades)
    day_selection = days |> Map.new(fn d -> {d, true} end)

    # Filtered trades based on selection
    filtered_trades = filter_trades_by_days(annotated_trades, day_selection)

    {summary_by_symbol, summary_total} = summarize_realized_pl(filtered_trades)
    # Mark aggregated items that already exist in DB so Save/Status reflect reality
    summary_by_symbol = annotate_summary_with_exists(summary_by_symbol)
    period = compute_period_from_trades(annotated_trades)
    unsaved_count = count_unsaved(filtered_trades)

    # Selected business days (Mon-Fri) count from selected toggles
    selected_days_count =
      day_selection
      |> Enum.filter(fn {d, on?} -> on? and weekday?(parse_date!(d)) end)
      |> length()

    {:ok,
     socket
     |> assign(:all_trades, annotated_trades)
     |> assign(:activity_data, filtered_trades)
     |> assign(:unsaved_count, unsaved_count)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:days, days)
     |> assign(:day_selection, day_selection)
     |> assign(:selected_days, selected_days_count)
     |> assign(:statement_period, period)
     |> assign(:summary_expanded, false)
     |> assign(:activity_expanded, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Activity Statement</h1>

        <p class="mt-2 text-gray-600">View your account activity and transaction history</p>

        <%= if @statement_period do %>
          <p class="mt-1 text-sm text-gray-500">
            Statement Date: <span class="font-medium text-gray-700">{@statement_period}</span>
          </p>
        <% end %>
      </div>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
        <!-- Day toggles -->
        <div class="px-6 pt-4 pb-2 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-sm text-gray-600 mr-2">Filter days:</span>
              <%= for day <- @days do %>
                <% on? = Map.get(@day_selection, day, true) %>
                <button
                  type="button"
                  phx-click="toggle_day"
                  phx-value-day={day}
                  class={[
                    "inline-flex items-center px-2.5 py-1.5 text-xs font-medium rounded-md border",
                    if(on?,
                      do: "bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100",
                      else: "bg-gray-50 text-gray-500 border-gray-200 hover:bg-gray-100"
                    )
                  ]}
                  aria-pressed={on?}
                >
                  {friendly_day_label(day)}
                </button>
              <% end %>
            </div>
            <div class="flex items-center gap-2">
              <button
                phx-click="select_all_days"
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
              >
                All
              </button>
              <button
                phx-click="deselect_all_days"
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
              >
                None
              </button>
            </div>
          </div>
        </div>
        
    <!-- Summary: Realized P/L by Symbol -->
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-gray-900">Summary (Realized P/L by Symbol)</h2>

              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
                {length(@summary_by_symbol)}
              </span>

              <button
                phx-click="toggle_summary"
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
                aria-expanded={@summary_expanded}
                aria-controls="summary-table"
              >
                <%= if @summary_expanded do %>
                  Collapse
                <% else %>
                  Expand
                <% end %>
              </button>
            </div>

            <.link
              navigate={~p"/activity_statement/upload"}
              class="inline-flex items-center px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-md hover:bg-blue-100"
            >
              Upload New Statement
            </.link>
          </div>
        </div>

        <ActivityStatementSummary.summary_table
          rows={@summary_by_symbol}
          total={@summary_total}
          expanded={@summary_expanded}
          selected_days={@selected_days}
          id="summary-table"
          on_save_all_aggregated?="save_all_aggregated"
          on_save_row_event="save_aggregated_row"
        />
        
    <!-- Unsaved records indicator -->
        <div class="px-6 py-3 border-b border-gray-200 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span class="text-sm text-gray-600">Unsaved records:</span>
            <span class={[
              "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
              if(@unsaved_count > 0,
                do: "bg-yellow-100 text-yellow-800",
                else: "bg-green-100 text-green-800"
              )
            ]}>
              {@unsaved_count}
            </span>
          </div>
          <%= if @unsaved_count > 0 do %>
            <span class="text-xs text-gray-500">Click "Save all" or save individual rows.</span>
          <% end %>
        </div>

        <ActivityStatementList.list
          id="activity-table"
          title="Recent Activity"
          count={length(@activity_data)}
          rows={@activity_data}
          expanded={@activity_expanded}
          toggle_event="toggle_activity"
          show_save_controls?={true}
          on_save_all?="save_all"
          on_upload_path?={~p"/activity_statement/upload"}
          on_save_row_event="save_row"
          show_values?={true}
        />

        <%= if Enum.empty?(@activity_data) do %>
          <div class="px-6 py-12 text-center">
            <div class="mx-auto w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-4">
              <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                />
              </svg>
            </div>

            <h3 class="text-sm font-medium text-gray-900 mb-2">No activity data available</h3>

            <p class="text-sm text-gray-500 mb-4">
              Upload CSV file(s) to view your activity statement
            </p>

            <.link
              navigate={~p"/activity_statement/upload"}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700"
            >
              Upload Statement
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Load and combine trades from all CSV files saved in priv/uploads
  defp load_all_trades do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()

    csv_files =
      case File.ls(uploads_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.map(&Path.join(uploads_dir, &1))

        _ ->
          []
      end

    csv_files
    |> Enum.flat_map(fn path ->
      try do
        ActivityStatementParser.parse_trades_file(path)
      rescue
        _ -> []
      end
    end)
  end

  # Get unique trade dates as ISO date strings, sorted ascending
  defp unique_trade_dates(trades) do
    trades
    |> Enum.map(&date_only(Map.get(&1, :datetime)))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Build a human-friendly period string from the min/max trade dates present
  defp compute_period_from_trades(trades) do
    dates =
      trades
      |> Enum.map(&date_only(Map.get(&1, :datetime)))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&parse_date!/1)

    case dates do
      [] ->
        nil

      list ->
        min_d = Enum.min(list, Date)
        max_d = Enum.max(list, Date)

        cond do
          Date.compare(min_d, max_d) == :eq ->
            Calendar.strftime(min_d, "%B %-d, %Y")

          true ->
            Calendar.strftime(min_d, "%B %-d, %Y") <>
              " – " <> Calendar.strftime(max_d, "%B %-d, %Y")
        end
    end
  end

  # Summary helpers
  defp summarize_realized_pl(trades) do
    groups = Enum.group_by(trades, & &1.symbol)

    rows =
      groups
      |> Enum.map(fn {symbol, ts} ->
        sum = ts |> Enum.map(&to_number(&1.realized_pl)) |> Enum.sum()
        # Close trades are those with inferred position_action == "CLOSE"
        closes =
          Enum.filter(ts, fn r -> build_close(r) == "CLOSE" end)
          |> Enum.map(&put_aggregated_side/1)

        close_count = length(closes)
        close_positive_count = closes |> Enum.count(fn r -> to_number(r.realized_pl) > 0.0 end)

        days_traded =
          ts
          |> Enum.map(&date_only(Map.get(&1, :datetime)))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> length()

        %{
          symbol: symbol,
          realized_pl: sum,
          close_count: close_count,
          close_positive_count: close_positive_count,
          days_traded: days_traded,
          close_trades: closes
        }
      end)
      |> Enum.sort_by(& &1.symbol)

    total = rows |> Enum.map(& &1.realized_pl) |> Enum.sum()
    {rows, total}
  end

  # Compute the aggregated trade side as the opposite of the close trade side
  defp put_aggregated_side(row) when is_map(row) do
    side =
      case Map.get(row, :side) || Map.get(row, "side") do
        s when is_binary(s) ->
          String.downcase(s)

        _ ->
          q = to_number(Map.get(row, :quantity) || Map.get(row, "quantity") || 0)
          if q < 0, do: "short", else: "long"
      end

    agg = if side == "long", do: "SHORT", else: if(side == "short", do: "LONG", else: "-")
    Map.put(row, :aggregated_side, agg)
  end

  # Filter helpers
  defp filter_trades_by_days(trades, day_selection) when is_map(day_selection) do
    trades
    |> Enum.filter(fn row ->
      case date_only(Map.get(row, :datetime)) do
        nil -> false
        d -> Map.get(day_selection, d, true)
      end
    end)
    |> Activity.dedupe_by_datetime_symbol()
  end

  defp date_only(nil), do: nil
  defp date_only(%DateTime{} = dt), do: Date.to_iso8601(DateTime.to_date(dt))
  defp date_only(%NaiveDateTime{} = ndt), do: Date.to_iso8601(NaiveDateTime.to_date(ndt))

  defp date_only(
         <<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), _::binary>>
       ),
       do: y <> "-" <> m <> "-" <> d

  defp date_only(bin) when is_binary(bin) do
    case String.split(bin) do
      [date | _] -> date_only(date)
      _ -> nil
    end
  end

  defp parse_date!(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>) do
    {:ok, dt} = Date.from_iso8601(y <> "-" <> m <> "-" <> d)
    dt
  end

  defp parse_param_datetime(nil), do: nil

  defp parse_param_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} ->
        DateTime.truncate(dt, :second)

      _ ->
        case NaiveDateTime.from_iso8601(s) do
          {:ok, ndt} ->
            NaiveDateTime.truncate(ndt, :second)

          _ ->
            case date_only(s) do
              <<_::binary-size(10)>> = iso -> NaiveDateTime.new!(parse_date!(iso), ~T[00:00:00])
              _ -> nil
            end
        end
    end
  end

  # Build a NaiveDateTime/DateTime from an item; if only a date is present, default to midnight
  defp coerce_item_datetime(item) do
    case Map.get(item, :datetime) || Map.get(item, "datetime") do
      %DateTime{} = dt ->
        dt
        |> DateTime.shift_zone!("Etc/UTC")
        |> DateTime.truncate(:second)
        |> DateTime.to_naive()

      %NaiveDateTime{} = ndt ->
        NaiveDateTime.truncate(ndt, :second)

      s when is_binary(s) ->
        case DateTime.from_iso8601(s) do
          {:ok, dt, _} ->
            dt
            |> DateTime.shift_zone!("Etc/UTC")
            |> DateTime.truncate(:second)
            |> DateTime.to_naive()

          _ ->
            case NaiveDateTime.from_iso8601(s) do
              {:ok, ndt} ->
                NaiveDateTime.truncate(ndt, :second)

              _ ->
                case date_only(s) do
                  <<_::binary-size(10)>> = iso ->
                    d = parse_date!(iso)
                    NaiveDateTime.new!(d, ~T[00:00:00])

                  _ ->
                    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
                end
            end
        end

      nil ->
        case Map.get(item, :date) || Map.get(item, "date") do
          %Date{} = d ->
            NaiveDateTime.new!(d, ~T[00:00:00])

          <<_::binary-size(10)>> = iso ->
            d = parse_date!(iso)
            NaiveDateTime.new!(d, ~T[00:00:00])

          _ ->
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
        end

      _ ->
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
    end
  end

  defp weekday?(%Date{} = d), do: Date.day_of_week(d) in 1..5

  defp to_number(nil), do: 0.0
  defp to_number(""), do: 0.0

  defp to_number(val) when is_binary(val) do
    val
    |> String.trim()
    |> String.replace(",", "")
    |> case do
      "" ->
        0.0

      s ->
        case Float.parse(s) do
          {n, _} -> n
          :error -> 0.0
        end
    end
  end

  # Support Decimal values from DB or parser
  defp to_number(%Decimal{} = d) do
    # Convert to float; acceptable for zero/non-zero checks and summary
    Decimal.to_float(d)
  end

  defp to_number(val) when is_number(val), do: val * 1.0

  defp build_close(row) do
    # Prefer existing persisted flag if available; else infer from realized_pl as requested
    cond do
      is_map(row) and Map.get(row, :position_action) in ["build", "close"] ->
        row.position_action |> String.upcase()

      true ->
        n = to_number(Map.get(row, :realized_pl))

        if n == 0 do
          "BUILD"
        else
          "CLOSE"
        end
    end
  end

  @impl true
  def handle_event("save_all", _params, socket) do
    trades = socket.assigns.activity_data |> Activity.dedupe_by_datetime_symbol()

    try do
      {:ok, inserted} = Activity.save_activity_rows(trades)
      # refresh exists flags
      flags = Activity.rows_exist_flags(trades)

      updated =
        trades
        |> Enum.with_index()
        |> Enum.map(fn {row, i} -> Map.put(row, :exists, Enum.at(flags, i)) end)

      {:noreply,
       socket
       |> assign(:activity_data, updated)
       |> assign(:unsaved_count, count_unsaved(updated))
       |> put_flash(:info, "Saved #{inserted} new rows to DB")}
    rescue
      e ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{Exception.message(e)}")}
    end
  end

  @impl true
  def handle_event("save_all_aggregated", _params, socket) do
    # Build a flat list of aggregated/close trade items from the current summary rows
    items =
      socket.assigns.summary_by_symbol
      |> Enum.flat_map(fn row ->
        case Map.get(row, :aggregated_trades) || Map.get(row, :close_trades) do
          list when is_list(list) -> list
          _ -> []
        end
      end)

    # Transform into rows for the trades table
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      items
      |> Enum.map(fn item ->
        %{
          datetime: coerce_item_datetime(item),
          ticker:
            Map.get(item, :symbol) || Map.get(item, :ticker) || Map.get(item, :underlying) || "-",
          aggregated_side: Map.get(item, :aggregated_side) || "-",
          result: if(to_number(Map.get(item, :realized_pl)) > 0.0, do: "WIN", else: "LOSE"),
          realized_pl: to_number(Map.get(item, :realized_pl)) |> Decimal.from_float(),
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      {count, _} =
        Journalex.Repo.insert_all(
          "trades",
          rows,
          on_conflict: :nothing,
          conflict_target: [:datetime, :ticker, :aggregated_side, :realized_pl]
        )

      # Refresh the summary rows with existence markers so UI updates immediately
      updated_summary = annotate_summary_with_exists(socket.assigns.summary_by_symbol)

      {:noreply,
       socket
       |> assign(:summary_by_symbol, updated_summary)
       |> put_flash(:info, "Saved #{count} aggregated trade records")}
    rescue
      e ->
        {:noreply,
         socket |> put_flash(:error, "Failed to save aggregated trades: #{Exception.message(e)}")}
    end
  end

  @impl true
  def handle_event("save_aggregated_row", params, socket) do
    dt_val = Map.get(params, "datetime")
    ticker = Map.get(params, "ticker") || "-"
    side = Map.get(params, "side") || "-"
    pl_str = Map.get(params, "pl") || "0"

    pl =
      case Float.parse(to_string(pl_str)) do
        {n, _} -> n
        _ -> 0.0
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %{
      datetime: parse_param_datetime(dt_val) || DateTime.utc_now() |> DateTime.truncate(:second),
      ticker: ticker,
      aggregated_side: side,
      result: if(pl > 0.0, do: "WIN", else: "LOSE"),
      realized_pl: Decimal.from_float(pl),
      inserted_at: now,
      updated_at: now
    }

    try do
      {count, _} =
        Journalex.Repo.insert_all(
          "trades",
          [row],
          on_conflict: :nothing,
          conflict_target: [:datetime, :ticker, :aggregated_side, :realized_pl]
        )

      updated_summary =
        if count > 0 do
          maybe_mark_aggregated_exists(socket.assigns.summary_by_symbol, %{
            datetime: row.datetime,
            ticker: row.ticker,
            aggregated_side: row.aggregated_side,
            realized_pl: Decimal.to_float(row.realized_pl)
          })
        else
          socket.assigns.summary_by_symbol
        end

      {:noreply,
       socket
       |> assign(:summary_by_symbol, updated_summary)
       |> put_flash(:info, if(count > 0, do: "Saved", else: "Already exists"))}
    rescue
      e -> {:noreply, socket |> put_flash(:error, "Failed to save row: #{Exception.message(e)}")}
    end
  end

  # Moved helper functions to the bottom to keep handle_event clauses contiguous

  @impl true
  def handle_event("toggle_summary", _params, socket) do
    {:noreply, assign(socket, :summary_expanded, !socket.assigns.summary_expanded)}
  end

  @impl true
  def handle_event("toggle_activity", _params, socket) do
    {:noreply, assign(socket, :activity_expanded, !socket.assigns.activity_expanded)}
  end

  @impl true
  def handle_event("save_row", %{"index" => index_str}, socket) do
    with {idx, _} <- Integer.parse(to_string(index_str)),
         rows when is_list(rows) <-
           Activity.dedupe_by_datetime_symbol(socket.assigns.activity_data),
         row when is_map(row) <- Enum.at(rows, idx) do
      case Activity.save_activity_row(row) do
        {:ok, _} ->
          updated =
            rows
            |> List.update_at(idx, fn r -> Map.put(r, :exists, true) end)

          {:noreply,
           socket
           |> assign(:activity_data, updated)
           |> assign(:unsaved_count, count_unsaved(updated))
           |> put_flash(:info, "Row saved")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save row: #{inspect(reason)}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_day", %{"day" => day}, socket) do
    day_selection = Map.update(socket.assigns.day_selection, day, true, &(!&1))

    filtered_trades = filter_trades_by_days(socket.assigns.all_trades, day_selection)
    {summary_by_symbol, summary_total} = summarize_realized_pl(filtered_trades)
    summary_by_symbol = annotate_summary_with_exists(summary_by_symbol)
    unsaved_count = count_unsaved(filtered_trades)

    selected_days_count =
      day_selection
      |> Enum.filter(fn {d, on?} -> on? and weekday?(parse_date!(d)) end)
      |> length()

    {:noreply,
     socket
     |> assign(:day_selection, day_selection)
     |> assign(:activity_data, filtered_trades)
     |> assign(:unsaved_count, unsaved_count)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:selected_days, selected_days_count)}
  end

  @impl true
  def handle_event("select_all_days", _params, socket) do
    day_selection = socket.assigns.days |> Map.new(fn d -> {d, true} end)

    filtered_trades = filter_trades_by_days(socket.assigns.all_trades, day_selection)
    {summary_by_symbol, summary_total} = summarize_realized_pl(filtered_trades)
    summary_by_symbol = annotate_summary_with_exists(summary_by_symbol)
    unsaved_count = count_unsaved(filtered_trades)

    selected_days_count =
      day_selection
      |> Enum.filter(fn {d, on?} -> on? and weekday?(parse_date!(d)) end)
      |> length()

    {:noreply,
     socket
     |> assign(:day_selection, day_selection)
     |> assign(:activity_data, filtered_trades)
     |> assign(:unsaved_count, unsaved_count)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:selected_days, selected_days_count)}
  end

  @impl true
  def handle_event("deselect_all_days", _params, socket) do
    day_selection = socket.assigns.days |> Map.new(fn d -> {d, false} end)

    filtered_trades = filter_trades_by_days(socket.assigns.all_trades, day_selection)
    {summary_by_symbol, summary_total} = summarize_realized_pl(filtered_trades)
    summary_by_symbol = annotate_summary_with_exists(summary_by_symbol)
    unsaved_count = count_unsaved(filtered_trades)

    selected_days_count =
      day_selection
      |> Enum.filter(fn {d, on?} -> on? and weekday?(parse_date!(d)) end)
      |> length()

    {:noreply,
     socket
     |> assign(:day_selection, day_selection)
     |> assign(:activity_data, filtered_trades)
     |> assign(:unsaved_count, unsaved_count)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:selected_days, selected_days_count)}
  end

  # Friendly label like "Mon, Sep 30" for a YYYY-MM-DD string
  defp friendly_day_label(<<_::binary>> = iso_date) do
    d = parse_date!(iso_date)
    Calendar.strftime(d, "%a, %b %-d")
  end

  # Count trades that are not yet saved (exists is not true)
  defp count_unsaved(trades) when is_list(trades) do
    Enum.count(trades, fn row -> Map.get(row, :exists, false) != true end)
  end

  # Helper to mark an aggregated item as existing after a successful insert
  defp maybe_mark_aggregated_exists(rows, attrs) when is_list(rows) and is_map(attrs) do
    target_date = date_only(Map.get(attrs, :datetime))
    target_ticker = Map.get(attrs, :ticker)
    target_side = Map.get(attrs, :aggregated_side)
    target_pl = Map.get(attrs, :realized_pl) |> to_number()

    Enum.map(rows, fn row ->
      {list_key, items} =
        cond do
          is_list(Map.get(row, :aggregated_trades)) ->
            {:aggregated_trades, Map.get(row, :aggregated_trades)}

          is_list(Map.get(row, :close_trades)) ->
            {:close_trades, Map.get(row, :close_trades)}

          true ->
            {nil, []}
        end

      new_items =
        items
        |> Enum.map(fn item ->
          item_date = date_only(Map.get(item, :datetime)) || Map.get(item, :date)

          item_ticker =
            Map.get(item, :symbol) || Map.get(item, :ticker) || Map.get(item, :underlying)

          item_side = Map.get(item, :aggregated_side)
          item_pl = to_number(Map.get(item, :realized_pl))

          if item_date == target_date and item_ticker == target_ticker and
               item_side == target_side and item_pl == target_pl do
            Map.put(item, :exists, true)
          else
            item
          end
        end)

      if is_nil(list_key) do
        row
      else
        Map.put(row, list_key, new_items)
      end
    end)
  end

  # Annotate aggregated items in summary rows with :exists=true when a matching
  # record is already saved in the trades table. Matching is done on
  # date(datetime), ticker, aggregated_side, and realized_pl rounded to 2 decimals
  # (same as DB scale). This ensures Save/Status reflect DB across refreshes.
  defp annotate_summary_with_exists(rows) when is_list(rows) do
    items = collect_aggregated_items(rows)

    case items do
      [] ->
        rows

      list ->
        keyset = persisted_trades_keyset(list)

        Enum.map(rows, fn row ->
          {list_key, agg_items} =
            cond do
              is_list(Map.get(row, :aggregated_trades)) ->
                {:aggregated_trades, Map.get(row, :aggregated_trades)}

              is_list(Map.get(row, :close_trades)) ->
                {:close_trades, Map.get(row, :close_trades)}

              true ->
                {nil, []}
            end

          new_items =
            Enum.map(agg_items, fn item ->
              dt =
                Map.get(item, :datetime) || Map.get(item, "datetime") || Map.get(item, :date) ||
                  Map.get(item, "date")

              date = date_only(dt)

              ticker =
                Map.get(item, :symbol) || Map.get(item, :ticker) || Map.get(item, :underlying)

              side = Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side")
              pl = Map.get(item, :realized_pl)
              key = {date, ticker, side, round2(to_number(pl))}

              if MapSet.member?(keyset, key) do
                Map.put(item, :exists, true)
              else
                item
              end
            end)

          if is_nil(list_key), do: row, else: Map.put(row, list_key, new_items)
        end)
    end
  end

  defp annotate_summary_with_exists(other), do: other

  # Build a set of persisted keys for quick lookup
  defp persisted_trades_keyset(items) when is_list(items) do
    # Compute min/max dates and involved tickers to limit query scope
    dates =
      items
      |> Enum.map(fn it ->
        date_only(
          Map.get(it, :datetime) || Map.get(it, "datetime") || Map.get(it, :date) ||
            Map.get(it, "date")
        )
      end)
      |> Enum.reject(&is_nil/1)

    tickers =
      items
      |> Enum.map(fn it ->
        Map.get(it, :symbol) || Map.get(it, :ticker) || Map.get(it, :underlying)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case dates do
      [] ->
        MapSet.new()

      _ ->
        min_d = dates |> Enum.map(&parse_date!/1) |> Enum.min(Date)
        max_d = dates |> Enum.map(&parse_date!/1) |> Enum.max(Date)

        start_dt = DateTime.new!(min_d, ~T[00:00:00], "Etc/UTC")
        end_dt = DateTime.new!(max_d, ~T[23:59:59], "Etc/UTC")

        q =
          from t in "trades",
            where: t.datetime >= ^start_dt and t.datetime <= ^end_dt,
            where: t.ticker in ^tickers,
            select: {fragment("date(?)", t.datetime), t.ticker, t.aggregated_side, t.realized_pl}

        Journalex.Repo.all(q)
        |> Enum.map(fn {date, ticker, side, pl} ->
          {Date.to_iso8601(date), ticker, side, round2(to_number(pl))}
        end)
        |> MapSet.new()
    end
  end

  defp collect_aggregated_items(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(fn row ->
      cond do
        is_list(Map.get(row, :aggregated_trades)) -> Map.get(row, :aggregated_trades)
        is_list(Map.get(row, :close_trades)) -> Map.get(row, :close_trades)
        true -> []
      end
    end)
  end

  defp round2(nil), do: 0.0
  defp round2(n) when is_number(n), do: Float.round(n * 1.0, 2)
  defp round2(%Decimal{} = d), do: d |> Decimal.to_float() |> round2()

  defp round2(val) when is_binary(val) do
    case Float.parse(String.replace(val, ",", "") |> String.trim()) do
      {n, _} -> round2(n)
      :error -> 0.0
    end
  end
end

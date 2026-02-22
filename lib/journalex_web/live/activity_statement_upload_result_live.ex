defmodule JournalexWeb.ActivityStatementUploadResultLive do
  use JournalexWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias Journalex.ActivityStatementParser
  alias Journalex.Activity
  alias Journalex.Trades.ActionChainBuilder
  alias JournalexWeb.ActivityStatementSummary
  alias JournalexWeb.ActivityStatementList

  # Constants for data precision and date boundaries
  @decimal_scale 2
  @day_start_time ~T[00:00:00]
  @day_end_time ~T[23:59:59]

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

    weeks = group_days_by_week(days)

    {:ok,
     socket
     |> assign(:all_trades, annotated_trades)
     |> assign(:activity_data, filtered_trades)
     |> assign(:unsaved_count, unsaved_count)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:days, days)
     |> assign(:weeks, weeks)
     |> assign(:day_selection, day_selection)
     |> assign(:selected_days, selected_days_count)
     |> assign(:statement_period, period)
     |> assign(:summary_expanded, false)
     |> assign(:activity_expanded, true)
     |> assign(:activity_page, 1)
     |> assign(:activity_page_size, Journalex.Settings.get_activity_page_size())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <div class="flex items-center justify-between">
          <h1 class="text-3xl font-bold text-gray-900">Activity Statement Upload Result</h1>

          <button
            phx-click="delete_all_uploads"
            phx-confirm="Delete all uploaded CSV files? This cannot be undone."
            class="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-semibold rounded-md bg-red-600 text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 shadow-sm"
          >
            <svg
              class="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6M9 7h6m-7 0a2 2 0 012-2h4a2 2 0 012 2m-8 0H5m11 0h3"
              />
            </svg>
            Delete All Uploads
          </button>
        </div>

        <p class="mt-2 text-gray-600">View your account activity and transaction history</p>

        <%= if @statement_period do %>
          <p class="mt-1 text-sm text-gray-500">
            Statement Date: <span class="font-medium text-gray-700">{@statement_period}</span>
          </p>
        <% end %>
      </div>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
        <!-- Day toggles -->
        <div class="px-6 pt-4 pb-3 border-b border-gray-200">
          <!-- Header row: label + All/None -->
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium text-gray-700">Filter days:</span>
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
          <!-- One row per calendar week -->
          <div class="space-y-1.5">
            <%= for week <- @weeks do %>
              <%
                all_on?  = Enum.all?(week.days, &Map.get(@day_selection, &1, true))
                any_on?  = Enum.any?(week.days, &Map.get(@day_selection, &1, true))
                partial? = any_on? and not all_on?
              %>
              <div class="flex items-center gap-2 flex-wrap">
                <!-- Week-range toggle chip -->
                <button
                  type="button"
                  phx-click="toggle_week"
                  phx-value-days={Enum.join(week.days, ",")}
                  title={if all_on?, do: "Deselect week", else: "Select week"}
                  class={[
                    "inline-flex items-center px-2.5 py-1.5 text-xs font-semibold rounded-md border min-w-[7rem] justify-center",
                    cond do
                      all_on?  -> "bg-blue-600 text-white border-blue-600 hover:bg-blue-700"
                      partial? -> "bg-blue-100 text-blue-700 border-blue-400 hover:bg-blue-200"
                      true     -> "bg-gray-100 text-gray-500 border-gray-300 hover:bg-gray-200"
                    end
                  ]}
                >
                  {week.label}
                </button>
                <!-- Individual day buttons -->
                <%= for day <- week.days do %>
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
            <% end %>
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
          rows={
            Enum.slice(
              @activity_data,
              (@activity_page - 1) * @activity_page_size,
              @activity_page_size
            )
          }
          expanded={@activity_expanded}
          toggle_event="toggle_activity"
          show_save_controls?={true}
          on_save_all?="save_all"
          on_upload_path?={~p"/activity_statement/upload"}
          on_save_row_event="save_row"
          show_values?={true}
        />
        <%
          act_total = length(@activity_data)
          act_pages = max(1, div(act_total + @activity_page_size - 1, @activity_page_size))
          act_offset = (@activity_page - 1) * @activity_page_size
          act_from = if act_total == 0, do: 0, else: act_offset + 1
          act_to = min(act_offset + @activity_page_size, act_total)
        %>
        <%= if act_pages > 1 do %>
          <div class="px-6 py-3 border-t border-gray-100 flex items-center justify-between">
            <span class="text-xs text-gray-500">
              Showing {act_from}–{act_to} of {act_total} rows
            </span>
            <div class="flex items-center gap-2">
              <button
                phx-click="activity_page"
                phx-value-page={@activity_page - 1}
                disabled={@activity_page <= 1}
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                ← Prev
              </button>
              <span class="text-xs text-gray-600">{@activity_page} / {act_pages}</span>
              <button
                phx-click="activity_page"
                phx-value-page={@activity_page + 1}
                disabled={@activity_page >= act_pages}
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                Next →
              </button>
            </div>
          </div>
        <% end %>
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

  # Centralized uploads directory path
  defp uploads_dir do
    Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()
  end

  # Load and combine trades from all CSV files saved in priv/uploads
  defp load_all_trades do
    dir = uploads_dir()

    csv_files =
      case File.ls(dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.map(&Path.join(dir, &1))

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

  # Remove all uploaded CSV files; returns count removed
  defp delete_all_uploaded_files do
    dir = uploads_dir()

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".csv"))
        |> Enum.reduce(0, fn filename, acc ->
          path = Path.join(dir, filename)

          case File.rm(path) do
            :ok -> acc + 1
            {:error, _} -> acc
          end
        end)

      _ ->
        0
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

  defp decimal_from_value(nil), do: Decimal.new("0")
  defp decimal_from_value(%Decimal{} = d), do: Decimal.round(d, @decimal_scale)

  defp decimal_from_value(val) when is_integer(val),
    do: val |> Decimal.new() |> Decimal.round(@decimal_scale)

  defp decimal_from_value(val) when is_float(val) do
    val
    |> Decimal.from_float()
    |> Decimal.round(@decimal_scale)
  end

  defp decimal_from_value(val) when is_binary(val) do
    cleaned = val |> String.trim() |> String.replace(",", "")

    cond do
      cleaned == "" ->
        Decimal.new("0")

      true ->
        case Decimal.parse(cleaned) do
          {decimal, _} -> Decimal.round(decimal, @decimal_scale)
          :error -> Decimal.new("0")
        end
    end
  end

  defp decimal_from_value(_), do: Decimal.new("0")

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

    # Check if there are any items to save
    if Enum.empty?(items) do
      {:noreply, socket |> put_flash(:info, "No trades to save")}
    else
      # Get the date range from items to query activity statements
      dates =
        items
        |> Enum.map(fn item ->
          dt = coerce_item_datetime(item)

          datetime =
            if is_struct(dt, NaiveDateTime), do: DateTime.from_naive!(dt, "Etc/UTC"), else: dt

          DateTime.to_date(datetime)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      if Enum.empty?(dates) do
        {:noreply, socket |> put_flash(:error, "Cannot determine dates from trade items")}
      else
        min_date = Enum.min(dates, Date)
        max_date = Enum.max(dates, Date)

        # Query activity statements from database for the date range
        start_dt = DateTime.new!(min_date, @day_start_time, "Etc/UTC")
        end_dt = DateTime.new!(max_date, @day_end_time, "Etc/UTC")

        db_statements =
          from(s in Journalex.ActivityStatement,
            where: s.datetime >= ^start_dt and s.datetime <= ^end_dt,
            order_by: [asc: s.datetime]
          )
          |> Journalex.Repo.all()

        # Build action chains for all items using database statements (may be empty)
        {rows, _errors} = build_trade_rows_with_action_chains(items, db_statements)

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

          # Inform if some chains might be empty
          empty_chain_count = Enum.count(rows, fn r -> is_nil(r.action_chain) end)
          base_msg = "Saved #{count} aggregated trade records"
          msg =
            if empty_chain_count > 0, do: base_msg <> " (#{empty_chain_count} without action chains)", else: base_msg

          {:noreply,
           socket
           |> assign(:summary_by_symbol, updated_summary)
           |> put_flash(:info, msg)}
        rescue
          e ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Failed to save aggregated trades: #{Exception.message(e)}"
             )}
        end
      end
    end
  end

  @impl true
  def handle_event("delete_all_uploads", _params, socket) do
    removed = delete_all_uploaded_files()

    trades = []
    annotated_trades = trades
    days = []
    day_selection = %{}
    filtered_trades = []
    {summary_by_symbol, summary_total} = summarize_realized_pl(filtered_trades)
    period = nil
    unsaved_count = 0
    selected_days_count = 0

    {:noreply,
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
     |> assign(:weeks, [])
     |> assign(:activity_page, 1)
     |> put_flash(:info, "Deleted #{removed} uploaded file(s)")}
  end

  @impl true
  def handle_event("save_aggregated_row", params, socket) do
    dt_val = Map.get(params, "datetime")
    ticker = Map.get(params, "ticker") || "-"
    side = Map.get(params, "side") || "-"
    pl_str = Map.get(params, "pl") || "0"
    qty_str = Map.get(params, "quantity") || "0"

    pl =
      case Float.parse(to_string(pl_str)) do
        {n, _} -> n
        _ -> 0.0
      end

    qty =
      case Float.parse(to_string(qty_str)) do
        {n, _} -> n
        _ -> 0.0
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Build a temporary item map to pass to action chain builder
    temp_item = %{
      datetime: parse_param_datetime(dt_val) || DateTime.utc_now() |> DateTime.truncate(:second),
      symbol: ticker,
      ticker: ticker,
      quantity: qty,
      realized_pl: pl
    }

    # Query activity statements from database for this item's date
    item_dt =
      case temp_item.datetime do
        %DateTime{} = dt -> dt
        %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
        _ -> DateTime.utc_now()
      end

    item_date = DateTime.to_date(item_dt)
    start_dt = DateTime.new!(item_date, @day_start_time, "Etc/UTC")
    end_dt = DateTime.new!(item_date, @day_end_time, "Etc/UTC")

    db_statements =
      from(s in Journalex.ActivityStatement,
        where: s.datetime >= ^start_dt and s.datetime <= ^end_dt and s.symbol == ^ticker,
        order_by: [asc: s.datetime]
      )
      |> Journalex.Repo.all()

    if Enum.empty?(db_statements) do
      {:noreply,
       socket
       |> put_flash(
         :error,
         "No activity statements found in database for #{ticker} on #{Date.to_iso8601(item_date)}. Please save activity statements first."
       )}
    else
      # Build action chain for this single item using DB statements
      normalized_item = %{
        datetime: temp_item.datetime,
        ticker: ticker,
        quantity: qty,
        realized_pl: pl
      }

      action_chain =
        ActionChainBuilder.build_action_chain(
          normalized_item,
          all_statements: db_statements
        )

      if action_chain do
        pl_decimal = decimal_from_value(pl)
  result = if Decimal.cmp(pl_decimal, Decimal.new(0)) == :gt, do: "WIN", else: "LOSE"
        duration = calculate_duration_from_action_chain(action_chain)

        row = %{
          datetime: temp_item.datetime,
          ticker: ticker,
          aggregated_side: side,
          result: result,
          realized_pl: pl_decimal,
          action_chain: action_chain,
          duration: duration,
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
           |> put_flash(
             :info,
             if(count > 0, do: "Saved with action chain", else: "Already exists")
           )}
        rescue
          e ->
            {:noreply, socket |> put_flash(:error, "Failed to save row: #{Exception.message(e)}")}
        end
      else
        # Proceed to save without an action chain
        pl_decimal = decimal_from_value(pl)
  result = if Decimal.cmp(pl_decimal, Decimal.new(0)) == :gt, do: "WIN", else: "LOSE"
        row = %{
          datetime: temp_item.datetime,
          ticker: ticker,
          aggregated_side: side,
          result: result,
          realized_pl: pl_decimal,
          action_chain: nil,
          duration: nil,
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
           |> put_flash(:info, if(count > 0, do: "Saved without action chain", else: "Already exists"))}
        rescue
          e ->
            {:noreply, socket |> put_flash(:error, "Failed to save row: #{Exception.message(e)}")}
        end
      end
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
    page_offset =
      (Map.get(socket.assigns, :activity_page, 1) - 1) *
        Map.get(socket.assigns, :activity_page_size, 50)

    with {local_idx, _} <- Integer.parse(to_string(index_str)),
         rows when is_list(rows) <-
           Activity.dedupe_by_datetime_symbol(socket.assigns.activity_data),
         idx = page_offset + local_idx,
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
     |> assign(:selected_days, selected_days_count)
     |> assign(:activity_page, 1)}
  end

  @impl true
  def handle_event("toggle_week", %{"days" => days_str}, socket) do
    week_days = String.split(days_str, ",", trim: true)
    day_selection = socket.assigns.day_selection

    # All on? → turn all off. Otherwise → turn all on.
    all_on? = Enum.all?(week_days, &Map.get(day_selection, &1, true))
    new_value = not all_on?

    day_selection =
      Enum.reduce(week_days, day_selection, fn d, acc -> Map.put(acc, d, new_value) end)

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
     |> assign(:selected_days, selected_days_count)
     |> assign(:activity_page, 1)}
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
     |> assign(:selected_days, selected_days_count)
     |> assign(:activity_page, 1)}
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
     |> assign(:selected_days, selected_days_count)
     |> assign(:activity_page, 1)}
  end

  @impl true
  def handle_event("activity_page", %{"page" => page_str}, socket) do
    total = length(socket.assigns.activity_data)
    page_size = socket.assigns.activity_page_size
    total_pages = max(1, div(total + page_size - 1, page_size))

    page =
      case Integer.parse(to_string(page_str)) do
        {n, _} -> n |> max(1) |> min(total_pages)
        :error -> 1
      end

    {:noreply, assign(socket, :activity_page, page)}
  end

  # Friendly label like "Mon, Sep 30" for a YYYY-MM-DD string
  defp friendly_day_label(<<_::binary>> = iso_date) do
    d = parse_date!(iso_date)
    Calendar.strftime(d, "%a, %b %-d")
  end

  # Group a sorted list of ISO date strings into calendar weeks (Sun-start).
  # Returns a list of %{label: "Feb 17–21", days: [...]} maps.
  defp group_days_by_week(days) when is_list(days) do
    days
    |> Enum.group_by(fn iso ->
      d = parse_date!(iso)
      # Use Monday as week anchor, then subtract to get Sunday-start week key
      monday = Date.beginning_of_week(d, :monday)
      Date.add(monday, -1)
    end)
    |> Enum.sort_by(fn {sunday_key, _} -> sunday_key end, Date)
    |> Enum.map(fn {_sunday_key, week_days} ->
      sorted = Enum.sort(week_days)
      first_d = parse_date!(List.first(sorted))
      last_d  = parse_date!(List.last(sorted))

      label =
        if first_d.month == last_d.month do
          Calendar.strftime(first_d, "%b %-d") <> "–" <> Calendar.strftime(last_d, "%-d")
        else
          Calendar.strftime(first_d, "%b %-d") <> "–" <> Calendar.strftime(last_d, "%b %-d")
        end

      %{label: label, days: sorted}
    end)
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

  # Build trade rows with action chains using database activity statements
  # Delegates to ActionChainBuilder for the core logic
  defp build_trade_rows_with_action_chains(items, db_statements) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {rows, errors} =
      Enum.reduce(items, {[], []}, fn item, {acc_rows, acc_errors} ->
        # Normalize item to expected format
        normalized_item = %{
          datetime: coerce_item_datetime(item),
          ticker: Map.get(item, :symbol) || Map.get(item, :ticker) || Map.get(item, :underlying),
          quantity: extract_quantity_value(item),
          realized_pl: Map.get(item, :realized_pl)
        }

        # Use ActionChainBuilder with pre-loaded statements
        action_chain =
          ActionChainBuilder.build_action_chain(
            normalized_item,
            all_statements: db_statements
          )

        pl_decimal = decimal_from_value(Map.get(item, :realized_pl))
  result = if Decimal.cmp(pl_decimal, Decimal.new(0)) == :gt, do: "WIN", else: "LOSE"
        duration = if action_chain, do: calculate_duration_from_action_chain(action_chain), else: nil

        row = %{
          datetime: normalized_item.datetime,
          ticker: normalized_item.ticker || "-",
          aggregated_side: Map.get(item, :aggregated_side) || "-",
          result: result,
          realized_pl: pl_decimal,
          action_chain: action_chain,
          duration: duration,
          inserted_at: now,
          updated_at: now
        }

        {[row | acc_rows], acc_errors}
      end)

    {Enum.reverse(rows), Enum.uniq(Enum.reverse(errors))}
  end

  # Extract numeric quantity from various formats
  defp extract_quantity_value(item) do
    qty = Map.get(item, :quantity) || Map.get(item, "quantity")

    cond do
      is_number(qty) ->
        qty

      is_struct(qty, Decimal) ->
        Decimal.to_float(qty)

      is_binary(qty) ->
        case Float.parse(qty) do
          {n, _} -> n
          :error -> 0.0
        end

      true ->
        0.0
    end
  end

  # Calculate duration from action_chain map.
  # Returns duration in seconds, or nil if unable to calculate.
  defp calculate_duration_from_action_chain(action_chain) when is_map(action_chain) do
    with open_action when not is_nil(open_action) <- Map.get(action_chain, "1"),
         open_dt_str when is_binary(open_dt_str) <- Map.get(open_action, "datetime"),
         {:ok, open_dt, _} <- DateTime.from_iso8601(open_dt_str),
         close_key <- find_close_position_key(action_chain),
         close_action when not is_nil(close_action) <- Map.get(action_chain, close_key),
         close_dt_str when is_binary(close_dt_str) <- Map.get(close_action, "datetime"),
         {:ok, close_dt, _} <- DateTime.from_iso8601(close_dt_str) do
      DateTime.diff(close_dt, open_dt, :second)
    else
      _ -> nil
    end
  end

  defp calculate_duration_from_action_chain(_), do: nil

  # Find the key for the "close_position" action in the action_chain map
  defp find_close_position_key(action_chain) when is_map(action_chain) do
    action_chain
    |> Enum.find(fn {_key, action} ->
      is_map(action) and Map.get(action, "action") == "close_position"
    end)
    |> case do
      {key, _action} -> key
      nil -> nil
    end
  end

  # Moved helper functions to the bottom to keep handle_event clauses contiguous

  # Safely format DateTime/NaiveDateTime or string for display in flash/errors
  defp format_datetime_for_display(%DateTime{} = dt), do: DateTime.to_string(dt)

  defp format_datetime_for_display(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_string()
  end

  defp format_datetime_for_display(s) when is_binary(s), do: s
  defp format_datetime_for_display(other), do: inspect(other)
end

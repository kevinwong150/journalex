defmodule JournalexWeb.ActivityStatementDatesLive do
  use JournalexWeb, :live_view
  alias Journalex.Activity
  alias JournalexWeb.ActivityStatementSummary

  @impl true
  def mount(_params, _session, socket) do
    # Build a default calendar grid for the current month on first load
    today = Date.utc_today()
    first = %Date{year: today.year, month: today.month, day: 1}
    last = end_of_month(first)

    sd = yyyymmdd(first)
    ed = yyyymmdd(last)

    results =
      case Activity.list_activity_statements_between(sd, ed) do
        {:error, _} -> []
        list when is_list(list) -> list
      end

    default_grid = build_date_grid(sd, ed, results)

    {:ok,
     socket
     |> assign(:start_date, nil)
     |> assign(:end_date, nil)
     |> assign(:statements, [])
     |> assign(:summary_by_symbol, [])
     |> assign(:summary_total, 0.0)
     |> assign(:summary_expanded, false)
     |> assign(:activity_expanded, true)
     |> assign(:calendar_month, first)
     |> assign(:date_grid, default_grid)
     |> assign(:error, nil)}
  end

  defp sanitize_date(nil), do: nil
  defp sanitize_date(""), do: nil

  defp sanitize_date(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>),
    do: y <> m <> d

  defp sanitize_date(other) when is_binary(other) and byte_size(other) == 8, do: other
  defp sanitize_date(_), do: nil

  defp valid_range?(nil, _), do: false
  defp valid_range?(_, nil), do: false

  defp valid_range?(sd, ed) when is_binary(sd) and is_binary(ed) do
    case {to_date(sd), to_date(ed)} do
      {{:ok, d1}, {:ok, d2}} -> not Date.after?(d1, d2)
      _ -> false
    end
  end

  defp to_date(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>) do
    Date.from_iso8601(y <> "-" <> m <> "-" <> d)
  end

  defp to_date(_), do: {:error, :invalid}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl p-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">Activity Statements by Date Range</h1>

        <.link navigate={~p"/activity_statement"} class="text-blue-600 hover:underline">
          Back to Latest
        </.link>
      </div>

      <%= if not Enum.empty?(@date_grid) do %>
        <div class="mb-6">
          <JournalexWeb.MonthGrid.month_grid
            months={@date_grid}
            show_nav={true}
            current_month={@calendar_month}
            prev_event="prev_month"
            next_event="next_month"
            title="Dates"
            start_date={@start_date && parse_yyyymmdd(@start_date)}
            end_date={@end_date && parse_yyyymmdd(@end_date)}
          />
        </div>
      <% end %>

      <.simple_form for={%{}} as={:dates} phx-submit="submit_dates" class="mb-6">
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 items-end">
          <.input
            type="date"
            name="dates[start_date]"
            label="Start date"
            value={@start_date && format_input(@start_date)}
            required
          />
          <.input
            type="date"
            name="dates[end_date]"
            label="End date"
            value={@end_date && format_input(@end_date)}
            required
          />
          <div>
            <.button type="submit">Apply</.button>
          </div>
        </div>

        <%= if @error do %>
          <p class="mt-2 text-sm text-red-600">{@error}</p>
        <% end %>
      </.simple_form>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
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
          </div>
        </div>

        <ActivityStatementSummary.summary_table
          rows={@summary_by_symbol}
          total={@summary_total}
          expanded={@summary_expanded}
          id="summary-table"
        />

        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-gray-900">Results</h2>

              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
                {length(@statements)}
              </span>

              <button
                phx-click="toggle_activity"
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
                aria-expanded={@activity_expanded}
                aria-controls="activity-table"
              >
                <%= if @activity_expanded do %>
                  Collapse
                <% else %>
                  Expand
                <% end %>
              </button>
            </div>
          </div>
        </div>

        <div class={"overflow-x-auto #{unless @activity_expanded, do: "hidden"}"} id="activity-table">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date/Time
                </th>

                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Side
                </th>

                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Build/Close
                </th>

                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Symbol
                </th>

                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Asset
                </th>

                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Currency
                </th>

                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Qty
                </th>

                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Trade Px
                </th>

                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Proceeds
                </th>

                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Comm/Fee
                </th>

                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Realized P/L
                </th>
              </tr>
            </thead>

            <tbody class="bg-white divide-y divide-gray-200">
              <%= for s <- @statements do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{s.datetime}</td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {display_side(s.side)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {display_position_action(s.position_action)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{s.symbol}</td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {s.asset_category}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{s.currency}</td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {display_trimmed(s.quantity)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {display_trimmed(s.trade_price)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {display_trimmed(s.proceeds)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {display_trimmed(s.comm_fee)}
                  </td>

                  <td class={"px-6 py-4 whitespace-nowrap text-sm text-right #{pl_class_amount(to_number(s.realized_pl))}"}>
                    {display_trimmed(s.realized_pl)}
                  </td>
                </tr>
              <% end %>

              <%= if @statements == [] do %>
                <tr>
                  <td colspan="11" class="px-6 py-8 text-center text-sm text-gray-500">
                    Choose a start and end date, then Apply.
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    start_date = Map.get(params, "start_date")
    end_date = Map.get(params, "end_date")

    cond do
      is_binary(start_date) and is_binary(end_date) and String.length(start_date) == 8 and
          String.length(end_date) == 8 ->
        case Activity.list_activity_statements_between(start_date, end_date) do
          {:error, _} ->
            {:noreply,
             assign(socket,
               error: "Invalid date(s)",
               statements: [],
               summary_by_symbol: [],
               summary_total: 0.0,
               date_grid: [],
               start_date: start_date,
               end_date: end_date
             )}

          results when is_list(results) ->
            {summary_by_symbol, summary_total} = summarize_realized_pl(results)
            date_grid = build_date_grid(start_date, end_date, results)

            {:noreply,
             assign(socket,
               start_date: start_date,
               end_date: end_date,
               statements: results,
               summary_by_symbol: summary_by_symbol,
               summary_total: summary_total,
               date_grid: date_grid,
               error: nil
             )}
        end

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_dates", %{"dates" => %{"start_date" => sd, "end_date" => ed}}, socket) do
    sd = sanitize_date(sd)
    ed = sanitize_date(ed)

    case valid_range?(sd, ed) do
      true ->
        {:noreply,
         push_patch(socket, to: ~p"/activity_statement/dates?start_date=#{sd}&end_date=#{ed}")}

      false ->
        {:noreply, assign(socket, error: "Please select at least one day (start <= end).")}
    end
  end

  @impl true
  def handle_event("prev_month", _params, socket) do
    case socket.assigns do
      %{calendar_month: %Date{} = cm} ->
        new_first = shift_month(cm, -1)
        update_calendar_month(socket, new_first)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_month", _params, socket) do
    case socket.assigns do
      %{calendar_month: %Date{} = cm} ->
        new_first = shift_month(cm, 1)
        update_calendar_month(socket, new_first)

      _ ->
        {:noreply, socket}
    end
  end

  defp update_calendar_month(socket, %Date{} = first) do
    last = end_of_month(first)
    sd = yyyymmdd(first)
    ed = yyyymmdd(last)

    results =
      case Activity.list_activity_statements_between(sd, ed) do
        {:error, _} -> []
        list when is_list(list) -> list
      end

    grid = build_date_grid(sd, ed, results)

    {:noreply,
     socket
     |> assign(:calendar_month, first)
     |> assign(:date_grid, grid)}
  end

  # Summary helpers (Decimal-aware)
  defp summarize_realized_pl(statements) do
    groups = Enum.group_by(statements, & &1.symbol)

    rows =
      groups
      |> Enum.map(fn {symbol, ts} ->
        sum = ts |> Enum.map(&to_number(&1.realized_pl)) |> Enum.sum()
        %{symbol: symbol, realized_pl: sum}
      end)
      |> Enum.sort_by(& &1.symbol)

    total = rows |> Enum.map(& &1.realized_pl) |> Enum.sum()
    {rows, total}
  end

  defp to_number(nil), do: 0.0
  defp to_number(""), do: 0.0
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(n) when is_number(n), do: n * 1.0

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

  # Display helper: empty string for 0, otherwise trim trailing zeros and decimal point.
  defp display_trimmed(nil), do: ""
  defp display_trimmed(%Decimal{} = d), do: display_trimmed(Decimal.to_float(d))
  defp display_trimmed(n) when is_number(n), do: n |> :erlang.float_to_binary([{:decimals, 8}, :compact]) |> trim_trailing()
  defp display_trimmed(val) when is_binary(val) do
    case String.trim(val) do
      "" -> ""
      s ->
        case Float.parse(String.replace(s, ",", "")) do
          {n, _} -> display_trimmed(n)
          :error -> s
        end
    end
  end

  defp trim_trailing(str) when is_binary(str) do
    # remove trailing zeros after decimal and any trailing dot
    str
    |> String.replace(~r/\.0+$/, "")
    |> String.replace(~r/(\.\d*?)0+$/, "\\1")
    |> String.replace(~r/\.$/, "")
    |> case do
      "0" -> ""
      "0.0" -> ""
      other -> other
    end
  end

  defp pl_class_amount(n) when is_number(n) do
    cond do
      n < 0 -> "text-red-600"
      n > 0 -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp format_amount(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)

  defp display_side(nil), do: ""
  defp display_side(side) when is_binary(side), do: String.upcase(side)

  defp display_position_action(nil), do: ""
  defp display_position_action(val) when is_binary(val), do: String.upcase(val)

  # Build a calendar-like grid grouped by month between start and end (inclusive)
  defp build_date_grid(sd, ed, statements) when is_binary(sd) and is_binary(ed) do
    with {:ok, d1} <- to_date(sd), {:ok, d2} <- to_date(ed) do
      present =
        statements
        |> Enum.map(fn s -> s.datetime |> DateTime.to_date() end)
        |> MapSet.new()

      months_in_range(d1, d2)
      |> Enum.map(fn {y, m} ->
        first = Date.new!(y, m, 1)
        last = end_of_month(first)
        # Compute Sunday-first leading blanks
        # Mon=1..Sun=7
        dow = Date.day_of_week(first)
        leading = rem(dow, 7)

        month_days = Date.range(first, last) |> Enum.to_list()

        cells =
          List.duplicate(%{date: nil}, leading) ++
            Enum.map(month_days, fn d ->
              %{
                date: d,
                in_range: Date.compare(d, d1) != :lt and Date.compare(d, d2) != :gt,
                has: MapSet.member?(present, d)
              }
            end)

        trailing = rem(7 - rem(length(cells), 7), 7)
        padded = cells ++ List.duplicate(%{date: nil}, trailing)

        %{
          label: month_label(first),
          weeks: Enum.chunk_every(padded, 7)
        }
      end)
    else
      _ -> []
    end
  end

  defp build_date_grid(_, _, _), do: []

  defp months_in_range(%Date{} = d1, %Date{} = d2) do
    start = {d1.year, d1.month}
    stop = {d2.year, d2.month}
    do_months_in_range(start, stop, []) |> Enum.reverse()
  end

  defp do_months_in_range({y, m}, {y, m}, acc), do: [{y, m} | acc]

  defp do_months_in_range({y, m}, stop, acc) do
    next = if m == 12, do: {y + 1, 1}, else: {y, m + 1}
    do_months_in_range(next, stop, [{y, m} | acc])
  end

  defp end_of_month(%Date{year: y, month: m}) do
    last_day = :calendar.last_day_of_the_month(y, m)
    Date.new!(y, m, last_day)
  end

  defp month_label(%Date{year: y, month: m}) do
    month_names =
      ~w(January February March April May June July August September October November December)

    name = Enum.at(month_names, m - 1)
    "#{name} #{y}"
  end

  defp day_of_month(%Date{day: d}), do: d

  defp yyyymmdd(%Date{year: y, month: m, day: d}) do
    y_str = Integer.to_string(y) |> String.pad_leading(4, "0")
    m_str = Integer.to_string(m) |> String.pad_leading(2, "0")
    d_str = Integer.to_string(d) |> String.pad_leading(2, "0")
    y_str <> m_str <> d_str
  end

  defp shift_month(%Date{year: y, month: m}, delta) when is_integer(delta) do
    total = y * 12 + (m - 1) + delta
    ny = div(total, 12)
    nm = rem(total, 12) + 1
    Date.new!(ny, nm, 1)
  end

  @impl true
  def handle_event("toggle_summary", _params, socket) do
    {:noreply, assign(socket, :summary_expanded, !socket.assigns.summary_expanded)}
  end

  @impl true
  def handle_event("toggle_activity", _params, socket) do
    {:noreply, assign(socket, :activity_expanded, !socket.assigns.activity_expanded)}
  end

  defp format_input(nil), do: nil

  defp format_input(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>),
    do: y <> "-" <> m <> "-" <> d

  defp format_input(other), do: other

  # Convert "yyyymmdd" to %Date{} or nil
  defp parse_yyyymmdd(nil), do: nil
  defp parse_yyyymmdd(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>) do
    case Date.from_iso8601(y <> "-" <> m <> "-" <> d) do
      {:ok, date} -> date
      _ -> nil
    end
  end
  defp parse_yyyymmdd(_), do: nil
end

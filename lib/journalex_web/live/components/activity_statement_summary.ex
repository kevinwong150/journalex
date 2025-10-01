defmodule JournalexWeb.ActivityStatementSummary do
  @moduledoc """
  Function components for rendering the Activity Statement summary table
  (Realized P/L by Symbol) in expanded or collapsed form.

  Usage:

  	<JournalexWeb.ActivityStatementSummary.summary_table
  		rows={@summary_by_symbol}
  		total={@summary_total}
  		expanded={@summary_expanded}
  	/>
  """

  use JournalexWeb, :html
  alias Phoenix.LiveView.JS
  alias JournalexWeb.AggregatedTradeList

  attr :rows, :list,
    required: true,
    doc:
      "List of maps like %{symbol: String.t, realized_pl: number, winrate?: number | Decimal.t | String.t, close_positive_count?: integer, close_count?: integer, close_trades?: list}"

  attr :total, :any, required: true, doc: "Numeric total realized P/L"
  attr :expanded, :boolean, default: false, doc: "Whether to render the expanded rows view"
  attr :id, :string, default: "summary-table", doc: "DOM id for aria-controls"
  attr :total_winrate, :any, default: nil, doc: "Optional total winrate (0..1 or 0..100)"

  # New: control whether we initially group by ticker (true) or show a flat list (false)
  attr :group_by_ticker, :boolean,
    default: true,
    doc: "If true, render grouped-by-ticker table; if false, show a flat aggregated trades list"

  # New: show/hide the local view toggle UI
  attr :show_grouping_toggle, :boolean,
    default: true,
    doc: "Show a local UI toggle for grouping mode"

  attr :selected_days, :any,
    default: nil,
    doc: "Optional total number of selected business days (Mon-Fri)"

  def summary_table(assigns) do
    ~H"""
    <div class="overflow-x-auto" id={@id}>
      <!-- View toggle: grouped by ticker vs flat list -->
      <div :if={@show_grouping_toggle} class="flex items-center justify-end mb-3">
        <span class="text-xs text-gray-500 mr-2">View:</span>
        <% base_btn =
          "relative inline-flex items-center px-3 py-1 text-xs font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-blue-500 transition-colors" %>
        <% active_btn = "bg-blue-600 text-white hover:bg-blue-700" %>
        <% inactive_btn = "bg-white text-gray-700 hover:bg-gray-50" %>

        <div class="inline-flex items-stretch rounded-md shadow-sm ring-1 ring-inset ring-gray-300 overflow-hidden bg-white">
          <button
            id={@id <> "-btn-grouped"}
            type="button"
            class={[
              base_btn,
              "rounded-l-md",
              if(@group_by_ticker, do: active_btn, else: inactive_btn)
            ]}
            phx-click={
              JS.show(to: "#" <> @id <> "-grouped")
              |> JS.hide(to: "#" <> @id <> "-flat")
              |> JS.add_class(active_btn, to: "#" <> @id <> "-btn-grouped")
              |> JS.remove_class(active_btn, to: "#" <> @id <> "-btn-flat")
              |> JS.add_class(inactive_btn, to: "#" <> @id <> "-btn-flat")
              |> JS.remove_class(inactive_btn, to: "#" <> @id <> "-btn-grouped")
            }
            aria-pressed={@group_by_ticker}
            title="Group by ticker"
          >
            By Ticker
          </button>

          <button
            id={@id <> "-btn-flat"}
            type="button"
            class={[
              base_btn,
              "rounded-r-md -ml-px",
              if(@group_by_ticker, do: inactive_btn, else: active_btn)
            ]}
            phx-click={
              JS.show(to: "#" <> @id <> "-flat")
              |> JS.hide(to: "#" <> @id <> "-grouped")
              |> JS.add_class(active_btn, to: "#" <> @id <> "-btn-flat")
              |> JS.remove_class(active_btn, to: "#" <> @id <> "-btn-grouped")
              |> JS.add_class(inactive_btn, to: "#" <> @id <> "-btn-grouped")
              |> JS.remove_class(inactive_btn, to: "#" <> @id <> "-btn-flat")
            }
            aria-pressed={!@group_by_ticker}
            title="Flat aggregated list"
          >
            Flat list
          </button>
        </div>
      </div>
      
    <!-- Grouped-by-ticker summary table (default) -->
      <div id={@id <> "-grouped"} class={if(@group_by_ticker, do: nil, else: "hidden")}>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <!-- Total row placed above the column labels inside the thead -->
            <tr class="font-semibold">
              <td class="px-6 py-3 text-sm text-gray-900">Total</td>
              <td class="px-6 py-3 text-sm text-right text-gray-900">
                {format_winrate(compute_overall_winrate(@rows))}
              </td>
              <% {owins, ototal} = overall_trade_counts(@rows) %>
              <td class="px-6 py-3 text-sm text-right text-gray-900">{format_count(owins)}</td>
              <td class="px-6 py-3 text-sm text-right text-gray-900">{format_count(ototal)}</td>
              <td class="px-6 py-3 text-sm text-right text-gray-900">
                {format_count(@selected_days || overall_days_traded(@rows))}
              </td>
              <td class={"px-6 py-3 text-sm text-right #{pl_class_amount(@total)}"}>
                {format_amount(@total)}
              </td>
            </tr>
            <!-- Column labels -->
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Symbol
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Winrate
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Wins
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Close Trades
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Days
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Aggregated Realized P/L
              </th>
            </tr>
          </thead>

          <%= for row <- @rows do %>
            <% row_id = row_dom_id(row) %> <% details_id = row_id <> "-details" %>
            <tbody id={"group-" <> row_id} class="group bg-white divide-y divide-gray-200">
              <tr
                id={row_id}
                class="hover:bg-blue-50 group-hover:bg-blue-50 cursor-pointer transition-colors"
                phx-click={JS.toggle(to: "#" <> details_id)}
                phx-keydown={JS.toggle(to: "#" <> details_id)}
                tabindex="0"
                role="button"
                aria-controls={details_id}
                aria-expanded={@expanded}
              >
                <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-900 border-l-2 border-transparent group-hover:border-blue-400">
                  <% items = row_aggregated_trades(row) %>
                  <span :if={is_list(items) and length(items) > 0} class="mr-2 text-gray-500">▸</span> {row.symbol}
                </td>

                <td class="px-6 py-3 whitespace-nowrap text-sm text-right text-gray-900">
                  {format_winrate(per_row_winrate(row))}
                </td>
                <% {wins, total} = row_trade_counts(row) %>
                <td class="px-6 py-3 whitespace-nowrap text-sm text-right text-gray-900">
                  {format_count(elem({wins, total}, 0))}
                </td>

                <td class="px-6 py-3 whitespace-nowrap text-sm text-right text-gray-900">
                  {format_count(elem({wins, total}, 1))}
                </td>

                <td class="px-6 py-3 whitespace-nowrap text-sm text-right text-gray-900">
                  {format_count(row_days_traded(row))}
                </td>

                <td class={"px-6 py-3 whitespace-nowrap text-sm text-right #{pl_class_amount(to_float(Map.get(row, :realized_pl)))}"}>
                  {format_amount(row.realized_pl)}
                </td>
              </tr>

              <tr
                id={details_id}
                class={[
                  "bg-gray-50 group-hover:bg-blue-50 transition-colors",
                  if(@expanded, do: nil, else: "hidden")
                ]}
              >
                <td class="px-6 py-3 text-sm text-gray-900" colspan="6">
                  <% items = row_aggregated_trades(row) %>
                  <AggregatedTradeList.aggregated_trade_list items={items} />
                </td>
              </tr>
            </tbody>
          <% end %>
        </table>
      </div>
      
    <!-- Flat aggregated trades list -->
      <div id={@id <> "-flat"} class={if(@group_by_ticker, do: "hidden", else: nil)}>
        <!-- Preserve the Total row in flat list mode -->
        <div class="mb-2 overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr class="font-semibold">
                <td class="px-6 py-3 text-sm text-gray-900">Total</td>
                <td class="px-6 py-3 text-sm text-right text-gray-900">
                  {format_winrate(compute_overall_winrate(@rows))}
                </td>
                <% {owins, ototal} = overall_trade_counts(@rows) %>
                <td class="px-6 py-3 text-sm text-right text-gray-900">{format_count(owins)}</td>
                <td class="px-6 py-3 text-sm text-right text-gray-900">{format_count(ototal)}</td>
                <td class="px-6 py-3 text-sm text-right text-gray-900">
                  {format_count(@selected_days || overall_days_traded(@rows))}
                </td>
                <td class={"px-6 py-3 text-sm text-right #{pl_class_amount(@total)}"}>
                  {format_amount(@total)}
                </td>
              </tr>
              <!-- Column labels for the totals, separate from the list body below -->
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Symbol
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Winrate
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Wins
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Close Trades
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Days
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Aggregated Realized P/L
                </th>
              </tr>
            </thead>
          </table>
        </div>

        <% all_items = all_aggregated_items(@rows) %>
        <AggregatedTradeList.aggregated_trade_list
          items={all_items}
          sortable={true}
          default_sort_by={:date}
          default_sort_dir={:desc}
          id={@id <> "-flat-list"}
        />
      </div>
    </div>
    """
  end

  # Local helpers for formatting/classing numeric values
  defp pl_class_amount(n) when is_number(n) do
    cond do
      n < 0 -> "text-red-600"
      n > 0 -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp pl_class_amount(nil), do: "text-gray-900"

  defp format_amount(nil), do: "0.00"
  defp format_amount(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp format_amount(%Decimal{} = d), do: d |> Decimal.to_float() |> format_amount()

  defp format_amount(bin) when is_binary(bin) do
    case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
      {n, _} -> format_amount(n)
      :error -> "0.00"
    end
  end

  # Winrate formatting helper. Accepts numbers (<=1 => fraction, else percent),
  # Decimal, and strings (may contain '%' or commas). Nil/unparseable => "-".
  defp format_winrate(val) do
    cond do
      is_nil(val) ->
        "-"

      match?(%Decimal{}, val) ->
        val |> Decimal.to_float() |> format_winrate_number()

      is_binary(val) ->
        cleaned = val |> String.replace([",", "%"], "") |> String.trim()

        case Float.parse(cleaned) do
          {n, _} -> format_winrate_number(n)
          :error -> "-"
        end

      is_number(val) ->
        format_winrate_number(val)

      true ->
        "-"
    end
  end

  defp format_winrate_number(n) when is_number(n) do
    pct = if n <= 1.0, do: n * 100.0, else: n * 1.0
    :erlang.float_to_binary(pct, decimals: 2) <> "%"
  end

  # Simple integer formatting for counts
  defp format_count(nil), do: "0"
  defp format_count(n) when is_integer(n), do: Integer.to_string(n)
  defp format_count(n) when is_number(n), do: n |> trunc() |> Integer.to_string()
  defp format_count(%Decimal{} = d), do: d |> Decimal.to_integer() |> Integer.to_string()

  defp format_count(bin) when is_binary(bin) do
    case Integer.parse(String.trim(bin)) do
      {i, _} -> Integer.to_string(i)
      :error -> "0"
    end
  end

  # Compute per-row winrate as: positive close trades / total close trades.
  # Tries multiple row shapes for flexibility:
  # - explicit counts: :close_positive_count and :close_count
  # - alternative counts: :wins_count and :trades_count
  # - list of trades: :close_trades (each trade has :realized_pl)
  # - fallback: :winrate if provided (interpreted as fraction or percentage)
  defp per_row_winrate(row) when is_map(row) do
    case row_trade_counts(row) do
      {wins, total} when is_integer(wins) and is_integer(total) and total > 0 ->
        wins / total

      _ ->
        case Map.get(row, :winrate) do
          nil -> nil
          v -> to_fraction(v)
        end
    end
  end

  # Compute overall winrate across all tickers as:
  # (sum of positive close trades across all rows) / (sum of close trades across all rows)
  defp compute_overall_winrate(rows) when is_list(rows) do
    {wins, total} = overall_trade_counts(rows)

    cond do
      total > 0 -> wins / total
      true -> nil
    end
  end

  defp overall_trade_counts(rows) when is_list(rows) do
    rows
    |> Enum.map(&row_trade_counts/1)
    |> Enum.reduce({0, 0}, fn
      {w, t}, {aw, at} when is_integer(w) and is_integer(t) -> {aw + w, at + t}
      _, acc -> acc
    end)
  end

  # Days traded helpers. A row may already contain :days_traded; else try :dates or :trades with datetime.
  defp row_days_traded(row) do
    case Map.get(row, :days_traded) do
      n when is_integer(n) and n >= 0 ->
        n

      _ ->
        cond do
          is_list(Map.get(row, :dates)) ->
            Map.get(row, :dates) |> Enum.uniq() |> length()

          is_list(Map.get(row, :close_trades)) ->
            Map.get(row, :close_trades)
            |> Enum.map(&date_only(Map.get(&1, :datetime)))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()
            |> length()

          not is_nil(Map.get(row, :datetime)) or not is_nil(Map.get(row, :date)) ->
            1

          true ->
            Map.get(row, :days) || 0
        end
    end
  end

  defp overall_days_traded(rows) do
    rows |> Enum.map(&row_days_traded/1) |> Enum.reduce(0, &+/2)
  end

  defp date_only(nil), do: nil
  defp date_only(%DateTime{} = dt), do: Date.to_iso8601(DateTime.to_date(dt))
  defp date_only(%NaiveDateTime{} = ndt), do: Date.to_iso8601(NaiveDateTime.to_date(ndt))

  defp date_only(
         <<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), _::binary>>
       ),
       do: y <> "-" <> m <> "-" <> d

  defp date_only(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>),
    do: y <> "-" <> m <> "-" <> d

  defp date_only(bin) when is_binary(bin) do
    case String.split(bin) do
      [date | _] -> date_only(date)
      _ -> nil
    end
  end

  # Try to derive {wins, total} close trade counts from a row map.
  defp row_trade_counts(row) do
    cond do
      is_integer(Map.get(row, :close_positive_count)) and is_integer(Map.get(row, :close_count)) ->
        {Map.get(row, :close_positive_count), Map.get(row, :close_count)}

      is_integer(Map.get(row, :wins_count)) and is_integer(Map.get(row, :trades_count)) ->
        {Map.get(row, :wins_count), Map.get(row, :trades_count)}

      is_list(Map.get(row, :close_trades)) ->
        trades = Map.get(row, :close_trades)
        total = length(trades)
        wins = trades |> Enum.count(fn t -> to_float(Map.get(t, :realized_pl)) > 0.0 end)
        {wins, total}

      not is_nil(Map.get(row, :realized_pl)) ->
        # Single trade-like map
        {if(to_float(Map.get(row, :realized_pl)) > 0.0, do: 1, else: 0), 1}

      true ->
        # If we only have a precomputed winrate and a total count, estimate wins for aggregation
        # using either :close_count or :trades_count
        total = Map.get(row, :close_count) || Map.get(row, :trades_count)
        winrate = Map.get(row, :winrate)

        cond do
          is_integer(total) and total > 0 and not is_nil(winrate) ->
            frac = to_fraction(winrate) || 0.0
            wins = round(frac * total)
            {wins, total}

          true ->
            {nil, nil}
        end
    end
  end

  # Convert various winrate representations into a fraction between 0.0 and 1.0
  # Accepts numbers (<=1 assumed fraction, >1 assumed percent), Decimal, and strings (may contain '%').
  defp to_fraction(nil), do: nil
  defp to_fraction(%Decimal{} = d), do: d |> Decimal.to_float() |> to_fraction()

  defp to_fraction(bin) when is_binary(bin) do
    cleaned = bin |> String.replace([",", "%"], "") |> String.trim()

    case Float.parse(cleaned) do
      {n, _} -> to_fraction(n)
      :error -> nil
    end
  end

  defp to_fraction(n) when is_number(n) do
    frac = if n <= 1.0, do: n * 1.0, else: n / 100.0

    frac
    |> max(0.0)
    |> min(1.0)
  end

  defp to_float(nil), do: 0.0
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  defp to_float(bin) when is_binary(bin) do
    case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
      {n, _} -> n * 1.0
      :error -> 0.0
    end
  end

  # Build a flat list of all aggregated trade items across all rows
  defp all_aggregated_items(rows) when is_list(rows) do
    rows
    |> Enum.flat_map(fn r ->
      case row_aggregated_trades(r) do
        list when is_list(list) -> list
        _ -> []
      end
    end)
  end

  # Row helpers for expand/collapse and aggregated items
  defp row_dom_id(row) when is_map(row) do
    sym = Map.get(row, :symbol) || Map.get(row, "symbol") || :erlang.phash2(row)

    base =
      case sym do
        s when is_binary(s) -> sanitize_id("row-" <> s)
        n when is_integer(n) -> "row-" <> Integer.to_string(n)
        other -> "row-" <> sanitize_id(to_string(other))
      end

    base
  end

  defp sanitize_id(bin) when is_binary(bin) do
    bin
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-_.]/i, "-")
  end

  # Prefer an explicit :aggregated_trades list; fallback to :close_trades
  defp row_aggregated_trades(row) when is_map(row) do
    cond do
      is_list(Map.get(row, :aggregated_trades)) -> Map.get(row, :aggregated_trades)
      is_list(Map.get(row, :close_trades)) -> Map.get(row, :close_trades)
      true -> []
    end
  end

  # Try to produce a human-friendly label for an aggregated item
  defp item_label(item) when is_map(item) do
    cond do
      is_binary(Map.get(item, :label)) -> Map.get(item, :label)
      is_binary(Map.get(item, :group)) -> Map.get(item, :group)
      is_binary(Map.get(item, :date)) -> Map.get(item, :date)
      not is_nil(Map.get(item, :datetime)) -> date_only(Map.get(item, :datetime)) || "-"
      is_binary(Map.get(item, :id)) -> Map.get(item, :id)
      true -> "-"
    end
  end
end

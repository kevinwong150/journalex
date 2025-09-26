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

  attr :rows, :list, required: true, doc: "List of maps like %{symbol: String.t, realized_pl: number, winrate?: number | Decimal.t | String.t, close_positive_count?: integer, close_count?: integer, close_trades?: list}"
  attr :total, :any, required: true, doc: "Numeric total realized P/L"
  attr :expanded, :boolean, default: false, doc: "Whether to render the expanded rows view"
  attr :id, :string, default: "summary-table", doc: "DOM id for aria-controls"
  attr :total_winrate, :any, default: nil, doc: "Optional total winrate (0..1 or 0..100)"
  attr :selected_days, :any, default: nil, doc: "Optional total number of selected business days (Mon-Fri)"

  def summary_table(assigns) do
    ~H"""
    <div class="overflow-x-auto" id={@id}>
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
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

        <tbody class="bg-white divide-y divide-gray-200">
          <%= if @expanded do %>
            <%= for row <- @rows do %>
              <tr class="hover:bg-gray-50">
                <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-900">{row.symbol}</td>

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

                <td class={"px-6 py-3 whitespace-nowrap text-sm text-right #{pl_class_amount(row.realized_pl)}"}>
                  {format_amount(row.realized_pl)}
                </td>
              </tr>
            <% end %>
          <% end %>

          <tr class="bg-gray-50 font-semibold">
            <td class="px-6 py-3 text-sm text-gray-900">Total</td>

            <td class="px-6 py-3 text-sm text-right text-gray-900">
              {format_winrate(compute_overall_winrate(@rows))}
            </td>

            <% {owins, ototal} = overall_trade_counts(@rows) %>
            <td class="px-6 py-3 text-sm text-right text-gray-900">
              {format_count(owins)}
            </td>

            <td class="px-6 py-3 text-sm text-right text-gray-900">
              {format_count(ototal)}
            </td>

            <td class="px-6 py-3 text-sm text-right text-gray-900">
              {format_count(@selected_days || overall_days_traded(@rows))}
            </td>

            <td class={"px-6 py-3 text-sm text-right #{pl_class_amount(@total)}"}>
              {format_amount(@total)}
            </td>
          </tr>
        </tbody>
      </table>
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

  # Winrate formatting helper. Accepts:
  # - numbers: if <= 1.0 it's treated as a fraction; otherwise as a percentage value already
  # - Decimal: converted to float
  # - strings: may include commas or a trailing '%'; same <=1 rule applies after parsing
  # nil or unparseable values render as "-"
  defp format_winrate(nil), do: "-"
  defp format_winrate(%Decimal{} = d), do: d |> Decimal.to_float() |> format_winrate()

  defp format_winrate(bin) when is_binary(bin) do
    cleaned = bin |> String.replace([",", "%"], "") |> String.trim()
    case Float.parse(cleaned) do
      {n, _} -> format_winrate(n)
      :error -> "-"
    end
  end

  defp format_winrate(n) when is_number(n) do
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
      {wins, total} when is_integer(wins) and is_integer(total) and total > 0 -> wins / total
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
      n when is_integer(n) and n >= 0 -> n
      _ ->
        cond do
          is_list(Map.get(row, :dates)) -> Map.get(row, :dates) |> Enum.uniq() |> length()
          is_list(Map.get(row, :close_trades)) ->
            Map.get(row, :close_trades)
            |> Enum.map(&date_only(Map.get(&1, :datetime)))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()
            |> length()
          true -> Map.get(row, :days) || 0
        end
    end
  end

  defp overall_days_traded(rows) do
    rows |> Enum.map(&row_days_traded/1) |> Enum.reduce(0, &+/2)
  end

  defp date_only(nil), do: nil
  defp date_only(%DateTime{} = dt), do: Date.to_iso8601(DateTime.to_date(dt))
  defp date_only(%NaiveDateTime{} = ndt), do: Date.to_iso8601(NaiveDateTime.to_date(ndt))
  defp date_only(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), _::binary>>), do: y <> "-" <> m <> "-" <> d
  defp date_only(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>), do: y <> "-" <> m <> "-" <> d
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

          true -> {nil, nil}
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
end

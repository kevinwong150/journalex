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

  attr :rows, :list, required: true, doc: "List of maps like %{symbol: String.t, realized_pl: number, winrate: number | Decimal.t | String.t}"
  attr :total, :any, required: true, doc: "Numeric total realized P/L"
  attr :expanded, :boolean, default: false, doc: "Whether to render the expanded rows view"
  attr :id, :string, default: "summary-table", doc: "DOM id for aria-controls"
  attr :total_winrate, :any, default: nil, doc: "Optional total winrate (0..1 or 0..100)"

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
              Aggregated Realized P/L
            </th>
          </tr>
        </thead>

        <tbody class="bg-white divide-y divide-gray-200">
          <%= if @expanded do %>
            <%= for row <- @rows do %>
              <tr class="hover:bg-gray-50">
                <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-900">{row.symbol}</td>

                <td class="px-6 py-3 whitespace-nowrap text-sm text-right text-gray-900"></td>

                <td class={"px-6 py-3 whitespace-nowrap text-sm text-right #{pl_class_amount(row.realized_pl)}"}>
                  {format_amount(row.realized_pl)}
                </td>
              </tr>
            <% end %>
          <% end %>

          <tr class="bg-gray-50 font-semibold">
            <td class="px-6 py-3 text-sm text-gray-900">Total</td>

            <td class="px-6 py-3 text-sm text-right text-gray-900">
              {format_winrate(compute_winrate(@rows))}
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

  # Compute winrate from rows: count of symbols with positive realized_pl
  # divided by total number of distinct traded symbols.
  defp compute_winrate(rows) when is_list(rows) do
    symbols = rows |> Enum.map(& &1.symbol) |> Enum.uniq()
    total = length(symbols)

    if total == 0 do
      nil
    else
      # Ensure one row per symbol when counting wins
      wins =
        rows
        |> Enum.uniq_by(& &1.symbol)
        |> Enum.count(fn r -> to_float(Map.get(r, :realized_pl)) > 0.0 end)

      wins / total
    end
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

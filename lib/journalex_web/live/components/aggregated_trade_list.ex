defmodule JournalexWeb.AggregatedTradeList do
  @moduledoc """
  Function components for rendering a generic Aggregated Trade list table.

  Columns: Date, Ticker, Side, Result (WIN/LOSE), Realized P/L.

  This component is data-source agnostic: pass any list of aggregated trade
  items (not tied to a specific ticker). Each item can be a map with fields
  like:
  	- :date | :datetime (preferred for the Date column)
  	- :label | :group | :id (fallbacks for display if date is missing)
  	- :realized_pl (number | Decimal | string) used to determine Result and P/L

  Usage:

  	<JournalexWeb.AggregatedTradeList.aggregated_trade_list items={@items} />
  """

  use JournalexWeb, :html

  attr :items, :list,
    required: true,
    doc:
      "List of aggregated trade items. Each item may include realized_pl, winrate/counts, and date/label info"

  attr :id, :string, default: nil, doc: "Optional DOM id for the table container"
  attr :class, :string, default: nil, doc: "Optional extra CSS classes for the container"

  def aggregated_trade_list(assigns) do
    ~H"""
    <div class={Enum.join(Enum.reject(["overflow-x-auto", @class], &is_nil/1), " ")} id={@id}>
      <%= if is_list(@items) and length(@items) > 0 do %>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-100">
            <tr>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Date
              </th>
              
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Ticker
              </th>
              
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Side
              </th>
              
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Result
              </th>
              
              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Realized P/L
              </th>
            </tr>
          </thead>
          
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for item <- @items do %>
              <tr class="hover:bg-blue-50 transition-colors">
                <td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">{item_label(item)}</td>
                
                <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">
                  {item_ticker(item)}
                </td>
                
                <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">
                  {Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side") || "-"}
                </td>
                 <% res = result_label(Map.get(item, :realized_pl)) %>
                <td class={"px-4 py-2 whitespace-nowrap text-sm text-right #{result_class(res)}"}>
                  {res}
                </td>
                
                <td class={"px-4 py-2 whitespace-nowrap text-sm text-right #{pl_class_amount(to_float(Map.get(item, :realized_pl)))}"}>
                  {format_amount(Map.get(item, :realized_pl))}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% else %>
        <div class="text-sm text-gray-500">No aggregated trades available.</div>
      <% end %>
    </div>
    """
  end

  # Local helpers (duplicated for component independence). These mirror the
  # helpers used in ActivityStatementSummary for consistent formatting.
  defp pl_class_amount(n) when is_number(n) do
    cond do
      n < 0 -> "text-red-600"
      n > 0 -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp format_amount(%Decimal{} = d), do: d |> Decimal.to_float() |> format_amount()

  defp format_amount(bin) when is_binary(bin) do
    case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
      {n, _} -> format_amount(n)
      :error -> "0.00"
    end
  end

  # Result helpers
  defp result_label(pl) do
    if to_float(pl) > 0.0, do: "WIN", else: "LOSE"
  end

  defp result_class("WIN"), do: "text-green-600"
  defp result_class("LOSE"), do: "text-red-600"
  defp result_class(_), do: "text-gray-900"

  # Ticker helper: try multiple common keys and fall back gracefully
  defp item_ticker(item) when is_map(item) do
    val =
      Map.get(item, :symbol) ||
        Map.get(item, :ticker) ||
        Map.get(item, :underlying) ||
        Map.get(item, "symbol") ||
        Map.get(item, "ticker") ||
        Map.get(item, "underlying")

    cond do
      is_binary(val) -> val
      is_atom(val) -> Atom.to_string(val)
      is_number(val) -> to_string(val)
      true -> "-"
    end
  end

  # All complex side inference removed; data now includes :aggregated_side

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

  defp to_float(nil), do: 0.0
  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

  defp to_float(bin) when is_binary(bin) do
    case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
      {n, _} -> n * 1.0
      :error -> 0.0
    end
  end

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

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

  attr :rows, :list, required: true, doc: "List of %{symbol: String.t, realized_pl: number} maps"
  attr :total, :any, required: true, doc: "Numeric total realized P/L"
  attr :expanded, :boolean, default: false, doc: "Whether to render the expanded rows view"
  attr :id, :string, default: "summary-table", doc: "DOM id for aria-controls"

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
              Aggregated Realized P/L
            </th>
          </tr>
        </thead>
        
        <tbody class="bg-white divide-y divide-gray-200">
          <%= if @expanded do %>
            <%= for row <- @rows do %>
              <tr class="hover:bg-gray-50">
                <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-900">{row.symbol}</td>
                
                <td class={"px-6 py-3 whitespace-nowrap text-sm text-right #{pl_class_amount(row.realized_pl)}"}>
                  {format_amount(row.realized_pl)}
                </td>
              </tr>
            <% end %>
          <% end %>
          
          <tr class="bg-gray-50 font-semibold">
            <td class="px-6 py-3 text-sm text-gray-900">Total</td>
            
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
end

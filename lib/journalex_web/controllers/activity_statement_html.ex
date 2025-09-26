defmodule JournalexWeb.ActivityStatementHTML do
  use JournalexWeb, :html

  embed_templates "activity_statement_html/*"

  # Formats Decimal values by trimming trailing zeros and removing the decimal
  # point when not needed. Returns empty string for nil.
  def format_decimal(nil), do: ""
  def format_decimal(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  def format_decimal(v) when is_integer(v) or is_float(v), do: to_string(v)
  def format_decimal(v) when is_binary(v), do: v

  attr :statement, :map, required: true

  def statement_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <tbody class="bg-white divide-y divide-gray-200">
          <tr>
            <th class="px-4 py-2 text-left">Date/Time</th>
            <td class="px-4 py-2">{@statement.datetime}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Side</th>
            <td class="px-4 py-2">{@statement.side}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Position Action</th>
            <td class="px-4 py-2">{@statement.position_action}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Symbol</th>
            <td class="px-4 py-2">{@statement.symbol}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Asset Category</th>
            <td class="px-4 py-2">{@statement.asset_category}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Currency</th>
            <td class="px-4 py-2">{@statement.currency}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Quantity</th>
            <td class="px-4 py-2">{format_decimal(@statement.quantity)}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Trade Price</th>
            <td class="px-4 py-2">{format_decimal(@statement.trade_price)}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Proceeds</th>
            <td class="px-4 py-2">{format_decimal(@statement.proceeds)}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Comm/Fee</th>
            <td class="px-4 py-2">{format_decimal(@statement.comm_fee)}</td>
          </tr>

          <tr>
            <th class="px-4 py-2 text-left">Realized P/L</th>
            <td class="px-4 py-2">{format_decimal(@statement.realized_pl)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end

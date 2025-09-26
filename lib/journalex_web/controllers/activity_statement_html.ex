defmodule JournalexWeb.ActivityStatementHTML do
  use JournalexWeb, :html

  embed_templates "activity_statement_html/*"

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
            <td class="px-4 py-2">{@statement.quantity}</td>
          </tr>
          
          <tr>
            <th class="px-4 py-2 text-left">Trade Price</th>
            <td class="px-4 py-2">{@statement.trade_price}</td>
          </tr>
          
          <tr>
            <th class="px-4 py-2 text-left">Proceeds</th>
            <td class="px-4 py-2">{@statement.proceeds}</td>
          </tr>
          
          <tr>
            <th class="px-4 py-2 text-left">Comm/Fee</th>
            <td class="px-4 py-2">{@statement.comm_fee}</td>
          </tr>
          
          <tr>
            <th class="px-4 py-2 text-left">Realized P/L</th>
            <td class="px-4 py-2">{@statement.realized_pl}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end

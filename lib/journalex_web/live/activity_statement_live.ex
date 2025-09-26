defmodule JournalexWeb.ActivityStatementLive do
  use JournalexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Sample data for demonstration - replace with actual data loading
    sample_data = [
      %{date: "2024-01-15", description: "Monthly Investment", amount: "$1,250.00", type: "Deposit"},
      %{date: "2024-01-10", description: "Stock Purchase - AAPL", amount: "-$580.00", type: "Trade"},
      %{date: "2024-01-05", description: "Dividend Payment", amount: "$25.50", type: "Dividend"},
      %{date: "2024-01-01", description: "Account Opening", amount: "$5,000.00", type: "Deposit"}
    ]

    {:ok, assign(socket, :activity_data, sample_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Activity Statement</h1>
        <p class="mt-2 text-gray-600">View your account activity and transaction history</p>
      </div>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-gray-900">Recent Activity</h2>
            <.link navigate={~p"/activity_statement/upload"} class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700">
              Upload New Statement
            </.link>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Description
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Type
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Amount
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for activity <- @activity_data do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= activity.date %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= activity.description %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full #{
                      case activity.type do
                        "Deposit" -> "bg-green-100 text-green-800"
                        "Trade" -> "bg-blue-100 text-blue-800"
                        "Dividend" -> "bg-purple-100 text-purple-800"
                        _ -> "bg-gray-100 text-gray-800"
                      end
                    }"}>
                      <%= activity.type %>
                    </span>
                  </td>
                  <td class={"px-6 py-4 whitespace-nowrap text-sm font-medium text-right #{
                    if String.starts_with?(activity.amount, "-"), do: "text-red-600", else: "text-green-600"
                  }"}>
                    <%= activity.amount %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%= if Enum.empty?(@activity_data) do %>
          <div class="px-6 py-12 text-center">
            <div class="mx-auto w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-4">
              <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            </div>
            <h3 class="text-sm font-medium text-gray-900 mb-2">No activity data available</h3>
            <p class="text-sm text-gray-500 mb-4">Upload a CSV file to view your activity statement</p>
            <.link navigate={~p"/activity_statement/upload"} class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700">
              Upload Statement
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
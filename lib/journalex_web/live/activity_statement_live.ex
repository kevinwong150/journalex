defmodule JournalexWeb.ActivityStatementLive do
  use JournalexWeb, :live_view
  alias Journalex.ActivityStatementParser
  alias Journalex.Activity

  @impl true
  def mount(_params, _session, socket) do
    trades = load_latest_trades()
    # annotate each row with existence flag
    exists_flags = Activity.rows_exist_flags(trades)

    trades =
      trades
      |> Enum.with_index()
      |> Enum.map(fn {row, idx} -> Map.put(row, :exists, Enum.at(exists_flags, idx)) end)

    {summary_by_symbol, summary_total} = summarize_realized_pl(trades)
    period = load_latest_period()

    {:ok,
     socket
     |> assign(:activity_data, trades)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:statement_period, period)
     |> assign(:summary_expanded, false)
     |> assign(:activity_expanded, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Activity Statement</h1>

        <p class="mt-2 text-gray-600">View your account activity and transaction history</p>

        <%= if @statement_period do %>
          <p class="mt-1 text-sm text-gray-500">
            Statement Date: <span class="font-medium text-gray-700">{@statement_period}</span>
          </p>
        <% end %>
      </div>

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

            <.link
              navigate={~p"/activity_statement/upload"}
              class="inline-flex items-center px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-md hover:bg-blue-100"
            >
              Upload New Statement
            </.link>
          </div>
        </div>

        <%= if @summary_expanded do %>
          <div class="overflow-x-auto" id="summary-table">
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
                <%= for row <- @summary_by_symbol do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-900">{row.symbol}</td>

                    <td class={"px-6 py-3 whitespace-nowrap text-sm text-right #{pl_class_amount(row.realized_pl)}"}>
                      {format_amount(row.realized_pl)}
                    </td>
                  </tr>
                <% end %>

                <tr class="bg-gray-50 font-semibold">
                  <td class="px-6 py-3 text-sm text-gray-900">Total</td>

                  <td class={"px-6 py-3 text-sm text-right #{pl_class_amount(@summary_total)}"}>
                    {format_amount(@summary_total)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="overflow-x-auto" id="summary-table">
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
                <tr class="bg-gray-50 font-semibold">
                  <td class="px-6 py-3 text-sm text-gray-900">Total</td>

                  <td class={"px-6 py-3 text-sm text-right #{pl_class_amount(@summary_total)}"}>
                    {format_amount(@summary_total)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>

        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-gray-900">Recent Activity</h2>

              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
                {length(@activity_data)}
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

            <div class="flex items-center gap-2">
              <button
                phx-click="save_all"
                class="inline-flex items-center px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700 disabled:opacity-50"
                disabled={Enum.empty?(@activity_data)}
              >
                Save All to DB
              </button>

              <.link
                navigate={~p"/activity_statement/upload"}
                class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700"
              >
                Upload New Statement
              </.link>
            </div>
          </div>
        </div>

        <div class={"overflow-x-auto #{unless @activity_expanded, do: "hidden"}"} id="activity-table">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Save
                </th>

                <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>

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
              <%= for {activity, idx} <- Enum.with_index(@activity_data) do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-3 py-4 whitespace-nowrap text-sm">
                    <button
                      phx-click="save_row"
                      phx-value-index={idx}
                      class="inline-flex items-center px-2 py-1 bg-emerald-600 text-white text-xs font-medium rounded hover:bg-emerald-700 disabled:opacity-50"
                      disabled={activity[:exists] == true}
                    >
                      Save
                    </button>
                  </td>

                  <td class="px-3 py-4 whitespace-nowrap text-sm">
                    <%= if activity[:exists] == true do %>
                      <span class="inline-flex items-center text-green-600" title="Already saved">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M5 13l4 4L19 7"
                          />
                        </svg>
                      </span>
                    <% else %>
                      <span class="inline-flex items-center text-red-500" title="Not saved">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M6 18L18 6M6 6l12 12"
                          />
                        </svg>
                      </span>
                    <% end %>
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {activity.datetime}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {buy_sell(activity.quantity)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {build_close(activity)}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{activity.symbol}</td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {activity.asset_category}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {activity.currency}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {activity.quantity}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {activity.trade_price}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {activity.proceeds}
                  </td>

                  <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                    {activity.comm_fee}
                  </td>

                  <td class={"px-6 py-4 whitespace-nowrap text-sm text-right #{pl_class(activity.realized_pl)}"}>
                    {activity.realized_pl}
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
              Upload a CSV file to view your activity statement
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

  defp load_latest_trades do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()
    file_path = Path.join(uploads_dir, "latest_activity_statement.csv")

    if File.exists?(file_path) do
      try do
        ActivityStatementParser.parse_trades_file(file_path)
      rescue
        _ -> []
      end
    else
      []
    end
  end

  defp load_latest_period do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()
    file_path = Path.join(uploads_dir, "latest_activity_statement.csv")

    if File.exists?(file_path) do
      try do
        ActivityStatementParser.parse_period_file(file_path)
      rescue
        _ -> nil
      end
    else
      nil
    end
  end

  defp pl_class(nil), do: "text-gray-900"
  defp pl_class(<<"-", _rest::binary>>), do: "text-red-600"
  defp pl_class(_), do: "text-green-600"

  # Summary helpers
  defp summarize_realized_pl(trades) do
    groups = Enum.group_by(trades, & &1.symbol)

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

  defp pl_class_amount(n) when is_number(n) do
    cond do
      n < 0 -> "text-red-600"
      n > 0 -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp format_amount(n) when is_number(n) do
    :erlang.float_to_binary(n * 1.0, decimals: 2)
  end

  defp buy_sell(qty) do
    case to_number(qty) do
      n when is_number(n) and n < 0 -> "SELL"
      _ -> "BUY"
    end
  end

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
    trades = socket.assigns.activity_data || []

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
       |> put_flash(:info, "Saved #{inserted} new rows to DB")}
    rescue
      e ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{Exception.message(e)}")}
    end
  end

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
    with {idx, _} <- Integer.parse(to_string(index_str)),
         rows when is_list(rows) <- socket.assigns.activity_data,
         row when is_map(row) <- Enum.at(rows, idx) do
      case Activity.save_activity_row(row) do
        {:ok, _} ->
          updated =
            rows
            |> List.update_at(idx, fn r -> Map.put(r, :exists, true) end)

          {:noreply,
           socket
           |> assign(:activity_data, updated)
           |> put_flash(:info, "Row saved")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save row: #{inspect(reason)}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end
end

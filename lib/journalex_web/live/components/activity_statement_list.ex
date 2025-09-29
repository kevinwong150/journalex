defmodule JournalexWeb.ActivityStatementList do
  use JournalexWeb, :html

  # Public API: flexible list component for activity statements/trades
  # Assigns:
  # - id: DOM id for table container
  # - title: section title
  # - count: integer length to display in badge
  # - rows: list of maps/structs with fields (datetime, side/quantity, position_action/realized_pl, symbol, asset_category, currency, quantity, trade_price, proceeds, comm_fee, realized_pl, exists)
  # - expanded: boolean to show/hide table
  # - toggle_event: event name for expand/collapse button
  # - show_save_controls?: whether to show "Save" and "Status" columns and row-level buttons (main page only)
  # - on_save_all?: event name for Save All button (optional)
  # - on_upload_path?: path for upload link button (optional)
  # - on_save_row_event: event name for single row save (required if show_save_controls?)
  attr :id, :string, required: true
  attr :title, :string, default: "Activity"
  attr :count, :integer, default: 0
  attr :rows, :list, default: []
  attr :expanded, :boolean, default: true
  attr :toggle_event, :string, default: nil
  attr :show_save_controls?, :boolean, default: false
  attr :on_save_all?, :string, default: nil
  attr :on_upload_path?, :string, default: nil
  attr :on_save_row_event, :string, default: nil
  # Whether to render numeric/text values in the table cells. Dates view keeps them blank.
  attr :show_values?, :boolean, default: true
  # Optional row selection controls
  attr :selectable?, :boolean, default: false
  attr :selected_ids, :any, default: MapSet.new()
  attr :all_selected?, :boolean, default: false
  attr :on_toggle_row_event, :string, default: nil
  attr :on_toggle_all_event, :string, default: nil

  slot :inner_block

  def list(assigns) do
    ~H"""
    <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between gap-3">
          <div class="flex items-center gap-3">
            <h2 class="text-lg font-semibold text-gray-900">{@title}</h2>

            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
              {@count}
            </span>

            <%= if @toggle_event do %>
              <button
                phx-click={@toggle_event}
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
                aria-expanded={@expanded}
                aria-controls={@id}
              >
                <%= if @expanded do %>
                  Collapse
                <% else %>
                  Expand
                <% end %>
              </button>
            <% end %>
          </div>

          <div :if={@show_save_controls?} class="flex items-center gap-2">
            <button
              :if={@on_save_all?}
              phx-click={@on_save_all?}
              class="inline-flex items-center px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700 disabled:opacity-50"
              disabled={Enum.empty?(@rows)}
            >
              Save All to DB
            </button>

            <.link
              :if={@on_upload_path?}
              navigate={@on_upload_path?}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700"
            >
              Upload New Statement
            </.link>
          </div>
        </div>
      </div>

      <div class={"overflow-x-auto #{unless @expanded, do: "hidden"}"} id={@id}>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th :if={@selectable?} class="px-4 py-3">
                <input type="checkbox" phx-click={@on_toggle_all_event} checked={@all_selected?} />
              </th>
              <th
                :if={@show_save_controls?}
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Save
              </th>

              <th
                :if={@show_save_controls?}
                class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
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

              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Realized P/L
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
            </tr>
          </thead>

          <tbody class="bg-white divide-y divide-gray-200">
            <%= for {row, idx} <- Enum.with_index(@rows) do %>
              <tr class="hover:bg-gray-50">
                <td :if={@selectable?} class="px-4 py-3">
                  <input type="checkbox" phx-click={@on_toggle_row_event} phx-value-id={Map.get(row, :id)} checked={MapSet.member?(@selected_ids, Map.get(row, :id))} />
                </td>
                <td :if={@show_save_controls?} class="px-3 py-4 whitespace-nowrap text-sm">
                  <button
                    phx-click={@on_save_row_event}
                    phx-value-index={idx}
                    class="inline-flex items-center px-2 py-1 bg-emerald-600 text-white text-xs font-medium rounded hover:bg-emerald-700 disabled:opacity-50"
                    disabled={Map.get(row, :exists) == true}
                  >
                    Save
                  </button>
                </td>

                <td :if={@show_save_controls?} class="px-3 py-4 whitespace-nowrap text-sm">
                  <%= if Map.get(row, :exists) == true do %>
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
                  {display_datetime(row)}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{display_side(row)}</td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {display_build_close(row)}
                </td>

                <td class={"px-6 py-4 whitespace-nowrap text-sm text-right #{pl_class(realized(row))}"}>
                  {if @show_values?, do: display_number(realized(row)), else: ""}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {Map.get(row, :symbol)}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {Map.get(row, :asset_category)}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {Map.get(row, :currency)}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                  {if @show_values?, do: display_number(Map.get(row, :quantity)), else: ""}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                  {if @show_values?, do: display_number(Map.get(row, :trade_price)), else: ""}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                  {if @show_values?, do: display_number(Map.get(row, :proceeds)), else: ""}
                </td>

                <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-900">
                  {if @show_values?, do: display_number(Map.get(row, :comm_fee)), else: ""}
                </td>
              </tr>
            <% end %>

            <%= if Enum.empty?(@rows) do %>
              <tr>
                <td
                  colspan={
                    (if @show_save_controls?, do: 13, else: 11) + (if @selectable?, do: 1, else: 0)
                  }
                  class="px-6 py-8 text-center text-sm text-gray-500"
                >
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # Helpers shared by pages
  defp display_datetime(%{datetime: dt}), do: dt
  defp display_datetime(_), do: ""

  # If row has explicit side, use it; else infer from quantity
  defp display_side(%{side: side}) when is_binary(side), do: String.upcase(side)

  defp display_side(%{quantity: q}) do
    if(to_number(q) < 0, do: "SELL", else: "BUY")
  end

  defp display_side(_), do: ""

  # If row has position_action, use it; else infer from realized_pl (0 = BUILD, else CLOSE)
  defp display_build_close(%{position_action: pa}) when is_binary(pa), do: String.upcase(pa)

  defp display_build_close(row) when is_map(row) do
    n = to_number(Map.get(row, :realized_pl))
    if n == 0.0, do: "BUILD", else: "CLOSE"
  end

  defp display_build_close(_), do: ""

  defp realized(row), do: Map.get(row, :realized_pl)

  defp pl_class(nil), do: "text-gray-900"
  defp pl_class(<<"-", _rest::binary>>), do: "text-red-600"

  defp pl_class(%Decimal{} = d) do
    cond do
      Decimal.compare(d, 0) == :lt -> "text-red-600"
      Decimal.compare(d, 0) == :gt -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp pl_class(n) when is_number(n) do
    cond do
      n < 0 -> "text-red-600"
      n > 0 -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp pl_class(_), do: "text-green-600"

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

  # Number display: trim trailing zeros; keep zero as "0"
  defp display_number(nil), do: ""
  defp display_number(%Decimal{} = d), do: display_number(Decimal.to_float(d))

  defp display_number(n) when is_number(n) do
    n
    |> :erlang.float_to_binary([{:decimals, 8}, :compact])
    |> trim_trailing()
  end

  defp display_number(val) when is_binary(val) do
    case String.trim(val) do
      "" ->
        ""

      s ->
        case Float.parse(String.replace(s, ",", "")) do
          {n, _} -> display_number(n)
          :error -> s
        end
    end
  end

  defp trim_trailing(str) when is_binary(str) do
    # remove trailing zeros after decimal and any trailing dot; keep zero as "0"
    trimmed =
      str
      |> String.replace(~r/\.0+$/, "")
      |> String.replace(~r/(\.\d*?)0+$/, "\\1")
      |> String.replace(~r/\.$/, "")

    case trimmed do
      "" -> "0"
      other -> other
    end
  end
end

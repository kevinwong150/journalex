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

  attr :sortable, :boolean,
    default: false,
    doc: "Enable client-side sorting by clicking column headers"

  attr :default_sort_by, :atom,
    default: :date,
    doc: "Default sort column: :date | :ticker | :side | :result | :pl"

  attr :default_sort_dir, :atom, default: :desc, doc: "Default sort direction: :asc | :desc"

  # Optional: show Save/Status columns like ActivityStatementList and handle per-row save
  attr :show_save_controls?, :boolean,
    default: false,
    doc: "Show Save and Status columns with row-level save button"

  attr :on_save_row_event, :string,
    default: nil,
    doc: "Event name to emit on row Save click (receives phx-value-index)"

  # Optional row selection and statuses (to mirror statement list UX)
  attr :selectable?, :boolean,
    default: false,
    doc: "Show a selection checkbox column and emit toggle events"

  attr :selected_idx, :any,
    default: MapSet.new(),
    doc: "Set of selected row indexes (MapSet of integers)"

  attr :all_selected?, :boolean,
    default: false,
    doc: "Whether the Select All checkbox is checked"

  attr :on_toggle_row_event, :string,
    default: nil,
    doc: "Event name to emit when a row checkbox is toggled (phx-value-index)"

  attr :on_toggle_all_event, :string,
    default: nil,
    doc: "Event name to emit when the header Select All checkbox is clicked"

  attr :row_statuses, :map,
    default: %{},
    doc: "Map index => :exists | :missing | :error for row highlight"

  def aggregated_trade_list(assigns) do
    ~H"""
    <% sorted_items =
      if @sortable, do: sort_items(@items, @default_sort_by, @default_sort_dir), else: @items %>
    <div
      class={Enum.join(Enum.reject(["overflow-x-auto", @class], &is_nil/1), " ")}
      id={@id}
      data-current-sort-key={if(@sortable, do: Atom.to_string(@default_sort_by), else: nil)}
      data-current-sort-dir={if(@sortable, do: Atom.to_string(@default_sort_dir), else: nil)}
    >
      <%= if is_list(sorted_items) and length(sorted_items) > 0 do %>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-100">
            <tr>
              <th :if={@selectable?} class="px-3 py-2">
                <input type="checkbox" phx-click={@on_toggle_all_event} checked={@all_selected?} />
              </th>
              <th
                :if={@show_save_controls?}
                class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Save
              </th>
              <th
                :if={@show_save_controls?}
                class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Status
              </th>
              <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider select-none">
                <%= if @sortable do %>
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 hover:text-gray-700"
                    data-sort-key="date"
                  >
                    <span>Date</span>
                    <span
                      class={if(@default_sort_by == :date, do: nil, else: "hidden")}
                      data-sort-arrow
                    >
                      <%= if @default_sort_by == :date and @default_sort_dir == :desc do %>
                        ▼
                      <% else %>
                        ▲
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  Date
                <% end %>
              </th>

              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider select-none">
                <%= if @sortable do %>
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 hover:text-gray-700"
                    data-sort-key="ticker"
                  >
                    <span>Ticker</span>
                    <span
                      class={if(@default_sort_by == :ticker, do: nil, else: "hidden")}
                      data-sort-arrow
                    >
                      <%= if @default_sort_by == :ticker and @default_sort_dir == :desc do %>
                        ▼
                      <% else %>
                        ▲
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  Ticker
                <% end %>
              </th>

              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider select-none">
                <%= if @sortable do %>
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 hover:text-gray-700"
                    data-sort-key="side"
                  >
                    <span>Side</span>
                    <span
                      class={if(@default_sort_by == :side, do: nil, else: "hidden")}
                      data-sort-arrow
                    >
                      <%= if @default_sort_by == :side and @default_sort_dir == :desc do %>
                        ▼
                      <% else %>
                        ▲
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  Side
                <% end %>
              </th>

              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider select-none">
                <%= if @sortable do %>
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 hover:text-gray-700"
                    data-sort-key="result"
                  >
                    <span>Result</span>
                    <span
                      class={if(@default_sort_by == :result, do: nil, else: "hidden")}
                      data-sort-arrow
                    >
                      <%= if @default_sort_by == :result and @default_sort_dir == :desc do %>
                        ▼
                      <% else %>
                        ▲
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  Result
                <% end %>
              </th>

              <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider select-none">
                <%= if @sortable do %>
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 hover:text-gray-700"
                    data-sort-key="pl"
                  >
                    <span>Realized P/L</span>
                    <span class={if(@default_sort_by == :pl, do: nil, else: "hidden")} data-sort-arrow>
                      <%= if @default_sort_by == :pl and @default_sort_dir == :desc do %>
                        ▼
                      <% else %>
                        ▲
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  Realized P/L
                <% end %>
              </th>
            </tr>
          </thead>

          <tbody class="bg-white divide-y divide-gray-200">
            <%= for {item, idx} <- Enum.with_index(sorted_items) do %>
              <% res = result_label(Map.get(item, :realized_pl)) %>
              <tr
                class={[
                  "hover:bg-blue-50 transition-colors",
                  status_class(@row_statuses, idx)
                ]}
                data-date={Integer.to_string(item_sort_date(item))}
                data-ticker={String.upcase(item_ticker(item) || "-")}
                data-side={
                  (Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side") || "-")
                  |> to_string()
                  |> String.upcase()
                }
                data-result={res}
                data-pl={
                  :erlang.float_to_binary(to_float(Map.get(item, :realized_pl)), [
                    :compact,
                    {:decimals, 8}
                  ])
                }
              >
                <td :if={@selectable?} class="px-3 py-2 whitespace-nowrap text-sm">
                  <input
                    type="checkbox"
                    phx-click={@on_toggle_row_event}
                    phx-value-index={idx}
                    checked={MapSet.member?(@selected_idx || MapSet.new(), idx)}
                  />
                </td>
                <td :if={@show_save_controls?} class="px-3 py-2 whitespace-nowrap text-sm">
                  <button
                    :if={not is_nil(@on_save_row_event)}
                    phx-click={@on_save_row_event}
                    phx-value-index={idx}
                    phx-value-datetime={item_datetime_value(item)}
                    phx-value-ticker={item_ticker(item)}
                    phx-value-side={
                      Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side") || "-"
                    }
                    phx-value-pl={
                      :erlang.float_to_binary(to_float(Map.get(item, :realized_pl)), [
                        :compact,
                        {:decimals, 8}
                      ])
                    }
                    class="inline-flex items-center px-2 py-1 bg-emerald-600 text-white text-xs font-medium rounded hover:bg-emerald-700 disabled:opacity-50"
                    disabled={Map.get(item, :exists) == true}
                  >
                    Save
                  </button>
                </td>

                <td :if={@show_save_controls?} class="px-3 py-2 whitespace-nowrap text-sm">
                  <%= if Map.get(item, :exists) == true do %>
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

                <td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">{item_label(item)}</td>

                <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">
                  {item_ticker(item)}
                </td>

                <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">
                  {Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side") || "-"}
                </td>
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
        <%= if @sortable and not is_nil(@id) do %>
          <script>
            (function() {
              try {
                var root = document.getElementById("<%= Phoenix.HTML.Engine.html_escape(@id) %>");
                if (!root || root.dataset.initialized === 'true') return;
                root.dataset.initialized = 'true';
                var table = root.querySelector('table');
                var tbody = table.querySelector('tbody');
                var headerBtns = table.querySelectorAll('thead [data-sort-key]');
                function getRows() { return Array.prototype.slice.call(tbody.querySelectorAll('tr')); }
                function cmp(a, b, dir, key) {
                  var av = a.dataset[key] || '';
                  var bv = b.dataset[key] || '';
                  var numKeys = { date: true, pl: true };
                  if (numKeys[key]) {
                    var an = parseFloat(av) || 0; var bn = parseFloat(bv) || 0;
                    return dir === 'asc' ? an - bn : bn - an;
                  } else {
                    av = av.toString(); bv = bv.toString();
                    var r = av.localeCompare(bv);
                    return dir === 'asc' ? r : -r;
                  }
                }
                function setArrows(activeKey, dir) {
                  headerBtns.forEach(function(btn){
                    var arrow = btn.querySelector('[data-sort-arrow]');
                    if (!arrow) return;
                    if (btn.dataset.sortKey === activeKey) {
                      arrow.classList.remove('hidden');
                      arrow.textContent = dir === 'desc' ? '▼' : '▲';
                    } else {
                      arrow.classList.add('hidden');
                    }
                  });
                }
                headerBtns.forEach(function(btn){
                  btn.addEventListener('click', function(){
                    var key = btn.dataset.sortKey;
                    var currentKey = root.dataset.currentSortKey || 'date';
                    var currentDir = root.dataset.currentSortDir || 'desc';
                    var dir = (key === currentKey) ? (currentDir === 'desc' ? 'asc' : 'desc') : 'asc';
                    var rows = getRows();
                    rows.sort(function(r1, r2){ return cmp(r1, r2, dir, key); });
                    rows.forEach(function(r){ tbody.appendChild(r); });
                    root.dataset.currentSortKey = key;
                    root.dataset.currentSortDir = dir;
                    setArrows(key, dir);
                  });
                });
                // Ensure initial arrows reflect default sort
                setArrows(root.dataset.currentSortKey || 'date', root.dataset.currentSortDir || 'desc');
              } catch (e) { /* no-op */ }
            })();
          </script>
        <% end %>
      <% else %>
        <div class="text-sm text-gray-500">No aggregated trades available.</div>
      <% end %>
    </div>
    """
  end

  # Local helpers (duplicated for component independence). These mirror the
  defp status_class(statuses, idx) do
    case Map.get(statuses || %{}, idx) do
      :exists -> "bg-red-50"
      :missing -> "bg-green-50"
      :error -> "bg-yellow-50"
      _ -> ""
    end
  end

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

  # Sorting helpers
  defp sort_items(items, sort_by, sort_dir) when is_list(items) do
    dir = normalize_dir(sort_dir)
    key = normalize_key(sort_by)
    sorter = sorter_for(key)

    items
    |> Enum.sort_by(sorter, dir)
  end

  defp normalize_key(k) when k in [:date, :ticker, :side, :result, :pl], do: k

  defp normalize_key(k) when is_binary(k) do
    key =
      try do
        String.to_existing_atom(k)
      rescue
        ArgumentError -> :date
      end

    if key in [:date, :ticker, :side, :result, :pl], do: key, else: :date
  end

  defp normalize_key(_), do: :date

  defp normalize_dir(:asc), do: :asc
  defp normalize_dir(:desc), do: :desc
  defp normalize_dir("asc"), do: :asc
  defp normalize_dir("desc"), do: :desc
  defp normalize_dir(_), do: :desc

  defp sorter_for(:date), do: &item_sort_date/1
  defp sorter_for(:ticker), do: &(item_ticker(&1) |> to_string() |> String.upcase())

  defp sorter_for(:side),
    do:
      &((Map.get(&1, :aggregated_side) || Map.get(&1, "aggregated_side") || "-")
        |> to_string()
        |> String.upcase())

  defp sorter_for(:result), do: &result_label(Map.get(&1, :realized_pl))
  defp sorter_for(:pl), do: &to_float(Map.get(&1, :realized_pl))

  # Return a numeric sortable date value (Gregorian days)
  defp item_sort_date(item) do
    with date when is_binary(date) <-
           date_only(
             Map.get(item, :datetime) || Map.get(item, :date) || Map.get(item, "datetime") ||
               Map.get(item, "date")
           ),
         {:ok, d} <- Date.from_iso8601(date) do
      :calendar.date_to_gregorian_days(Date.to_erl(d))
    else
      _ -> 0
    end
  end

  defp item_label(item) when is_map(item) do
    cond do
      is_binary(Map.get(item, :label)) -> Map.get(item, :label)
      is_binary(Map.get(item, :group)) -> Map.get(item, :group)
      # Prefer accurate datetime from the data source, but display as date only
      not is_nil(Map.get(item, :datetime)) -> date_only(Map.get(item, :datetime)) || "-"
      is_binary(Map.get(item, :date)) -> Map.get(item, :date)
      is_binary(Map.get(item, :id)) -> Map.get(item, :id)
      true -> "-"
    end
  end

  # Prefer full datetime string if present; else fall back to date only
  defp item_datetime_value(item) when is_map(item) do
    case Map.get(item, :datetime) || Map.get(item, "datetime") do
      %DateTime{} = dt ->
        DateTime.to_iso8601(dt)

      %NaiveDateTime{} = ndt ->
        NaiveDateTime.to_iso8601(ndt)

      s when is_binary(s) ->
        String.trim(s)

      _ ->
        case Map.get(item, :date) || Map.get(item, "date") do
          %Date{} = d -> Date.to_iso8601(d)
          s when is_binary(s) -> String.trim(s)
          _ -> ""
        end
    end
  end
end

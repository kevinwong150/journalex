defmodule JournalexWeb.AggregatedTradeList do
  @moduledoc """
  Function components for rendering a generic Aggregated Trade list table.

  Columns: Date, Ticker, Side, Result (WIN/LOSE), Duration, Realized P/L.

  Each trade row can be expanded to reveal a timeline-style action chain so the
  sequence of fills or adjustments stays easy to scan.

  Action chain data: each aggregated trade item can include a list of action
  maps (defaults to the `:actions` key, overridable with `:action_chain_key`).
  Every action may specify a timestamp, type/side label, quantity/contracts,
  price/P&L, and free-form notes. Available fields are rendered when present so
  the timeline stays flexible across data sources.

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

  attr :hidden_idx, :any,
    default: MapSet.new(),
    doc: "Set of row indexes to hide (display: none) without changing indices"

  attr :show_action_chain?, :boolean,
    default: true,
    doc: "Enable expandable action chain timeline under each trade row"

  attr :action_chain_key, :any,
    default: :actions,
    doc: "Key to read for the action chain list (atom or string). Falls back to :action_chain"

  # Optional: map of title (e.g. "TICKER@ISO8601") => Notion page id to display per row
  attr :page_ids_map, :map,
    default: %{},
    doc: "Map of row title to Notion page id (used to render a Page ID column)"

  # Optional: whether to show the Page ID column
  attr :show_page_id_column?, :boolean,
    default: false,
    doc: "Show a Page ID column using :page_ids_map lookups"

  # Optional: map index => diff map to show inconsistencies per row
  attr :row_inconsistencies, :map,
    default: %{},
    doc: "Map of row index => %{field => %{expected, actual}} for display"

  # Optional: whether to show an Inconsistencies column
  attr :show_inconsistency_column?, :boolean,
    default: false,
    doc: "Show a column indicating mismatched properties when present"

  # Metadata editing
  attr :show_metadata_column?, :boolean,
    default: false,
    doc: "Show a Metadata column with status and form in expandable row"

  attr :on_save_metadata_event, :string,
    default: nil,
    doc: "Event name to emit when metadata form is saved"

  attr :on_reset_metadata_event, :string,
    default: nil,
    doc: "Event name to emit when metadata form reset is requested"

  attr :on_sync_metadata_event, :string,
    default: nil,
    doc: "Event name to emit when sync from Notion is requested for a trade"

  attr :global_metadata_version, :integer,
    default: 2,
    doc: "Global version for metadata forms (all rows use same version)"

  attr :drafts, :list,
    default: [],
    doc: "List of metadata draft templates (pre-filtered by version)"

  attr :on_apply_draft_event, :string,
    default: nil,
    doc: "Event name to emit when a draft is applied to a trade row"

  def aggregated_trade_list(assigns) do
    ~H"""
    <% chain_key = @action_chain_key %>
    <% show_action_toggle? = @show_action_chain? %>
    <% hidden_idx = @hidden_idx || MapSet.new() %>
    <% sorted_items =
      if @sortable, do: sort_items(@items, @default_sort_by, @default_sort_dir), else: @items %>
    <div
      class={Enum.join(Enum.reject(["overflow-x-auto", @class], &is_nil/1), " ")}
      data-component="aggregated-trade-list"
      id={@id}
      phx-hook="AggregatedTradeList"
      data-current-sort-key={if(@sortable, do: Atom.to_string(@default_sort_by), else: nil)}
      data-current-sort-dir={if(@sortable, do: Atom.to_string(@default_sort_dir), else: nil)}
    >
      <%= if is_list(sorted_items) and length(sorted_items) > 0 do %>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-100">
            <tr>
              <th :if={show_action_toggle?} class="px-3 py-2 w-16 text-center align-middle">
                <span class="sr-only">Toggle action chain</span>
              </th>
              <th :if={@selectable?} class="px-3 py-2 w-8 text-center align-middle">
                <input
                  type="checkbox"
                  class="h-4 w-4 align-middle m-0 mx-auto"
                  phx-click={@on_toggle_all_event}
                  checked={@all_selected?}
                />
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
              <th
                :if={@show_inconsistency_column?}
                class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                title="Detected differences between this row and the Notion page"
              >
                Mismatch
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
                    data-sort-key="duration"
                  >
                    <span>Duration</span>
                    <span
                      class={if(@default_sort_by == :duration, do: nil, else: "hidden")}
                      data-sort-arrow
                    >
                      <%= if @default_sort_by == :duration and @default_sort_dir == :desc do %>
                        ▼
                      <% else %>
                        ▲
                      <% end %>
                    </span>
                  </button>
                <% else %>
                  Duration
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
              <th
                :if={@show_page_id_column?}
                class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider select-none"
              >
                Page ID
              </th>
              <th
                :if={@show_metadata_column?}
                class="px-4 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider select-none"
              >
                Metadata
              </th>
            </tr>
          </thead>

          <tbody class="bg-white divide-y divide-gray-200">
            <%= for {item, idx} <- Enum.with_index(sorted_items) do %>
              <% row_id = "row-" <> Integer.to_string(idx) %>
              <% chain = action_chain(item, chain_key) %>
              <% chain_length = length(chain) %>
              <% has_chain = show_action_toggle? and chain_length > 0 %>
              <% res = result_label(Map.get(item, :realized_pl)) %>
              <% is_hidden = MapSet.member?(hidden_idx, idx) %>
              <tr
                class={[
                  (is_hidden && "hidden") || nil,
                  "hover:bg-blue-50 transition-colors cursor-pointer",
                  status_class(@row_statuses, idx)
                ]}
                data-row-type="main"
                data-row-id={row_id}
                data-date={Integer.to_string(item_sort_date(item))}
                data-ticker={String.upcase(item_ticker(item) || "-")}
                data-side={
                  (Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side") || "-")
                  |> to_string()
                  |> String.upcase()
                }
                data-result={res}
                data-duration={Integer.to_string(Map.get(item, :duration) || 0)}
                data-pl={
                  :erlang.float_to_binary(to_float(Map.get(item, :realized_pl)), [
                    :compact,
                    {:decimals, 8}
                  ])
                }
              >
                <td
                  :if={show_action_toggle?}
                  class="px-3 py-2 whitespace-nowrap text-sm text-center align-middle"
                >
                  <button
                    type="button"
                    class="inline-flex h-7 w-7 items-center justify-center rounded-full border text-xs font-semibold transition border-slate-300 bg-white text-slate-600 hover:border-blue-200 hover:bg-blue-100 shadow-sm"
                    data-row-toggle={row_id}
                    aria-expanded="false"
                    aria-controls={"detail-" <> row_id}
                  >
                    <span data-toggle-icon class="leading-none">
                      ▸
                    </span>
                    <span class="sr-only">Toggle action chain ({chain_length} steps)</span>
                  </button>
                  <span
                    class={[
                      "ml-2 inline-flex items-center justify-center rounded-full px-1.5 text-[10px] font-semibold align-middle h-5 min-w-[1.25rem] shadow-sm",
                      (chain_length > 0 && "bg-blue-100 text-blue-700") ||
                        "bg-slate-100 text-slate-500"
                    ]}
                    title={"#{chain_length} step" <> if(chain_length == 1, do: "", else: "s")}
                  >
                    {chain_length}
                  </span>
                </td>
                <td
                  :if={@selectable?}
                  class="px-3 py-2 whitespace-nowrap text-sm text-center align-middle"
                >
                  <input
                    type="checkbox"
                    class="h-4 w-4 align-middle m-0 mx-auto"
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

                <td :if={@show_inconsistency_column?} class="px-3 py-2 whitespace-nowrap text-xs">
                  <% diffs = Map.get(@row_inconsistencies || %{}, idx) %>
                  <%= if is_map(diffs) and map_size(diffs) > 0 do %>
                    <% count = map_size(diffs) %>
                    <span
                      class="inline-flex items-center gap-1 rounded bg-amber-100 text-amber-800 px-2 py-0.5"
                      title={diffs_tooltip(diffs)}
                    >
                      <span class="text-[10px] font-semibold">{count}</span>
                      <span class="text-[11px]">diff</span>
                    </span>
                  <% else %>
                    <span class="text-[11px] text-slate-400">—</span>
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

                <td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">
                  {format_duration(Map.get(item, :duration))}
                </td>

                <td class={"px-4 py-2 whitespace-nowrap text-sm text-right #{pl_class_amount(to_float(Map.get(item, :realized_pl)))}"}>
                  {format_amount(Map.get(item, :realized_pl))}
                </td>
                <td
                  :if={@show_page_id_column?}
                  class="px-4 py-2 whitespace-nowrap text-xs text-gray-700"
                >
                  <% title_for_lookup = item_ticker(item) <> "@" <> item_datetime_value(item) %>
                  <%= if page_id = Map.get(@page_ids_map || %{}, title_for_lookup) do %>
                    <code class="text-[11px] bg-gray-100 rounded px-1 py-0.5">{page_id}</code>
                  <% else %>
                  <% end %>
                </td>
                <td
                  :if={@show_metadata_column?}
                  class="px-4 py-2 whitespace-nowrap text-xs text-center"
                >
                  <.metadata_version_badge
                    saved_version={Map.get(item, :metadata_version)}
                    global_version={@global_metadata_version}
                    has_data={not is_nil(Map.get(item, :metadata)) and map_size(Map.get(item, :metadata, %{})) > 0}
                    is_done={Map.get(Map.get(item, :metadata, %{}), :done?) == true}
                  />
                </td>
              </tr>
              <tr
                :if={show_action_toggle?}
                data-row-type="detail"
                data-parent={row_id}
                id={"detail-" <> row_id}
                class={["hidden bg-slate-50"]}
              >
                <td colspan={detail_colspan(assigns, show_action_toggle?)} class="px-6 py-4">
                  <% diffs = Map.get(@row_inconsistencies || %{}, idx) %>
                  <%= if is_map(diffs) and map_size(diffs) > 0 do %>
                    <div class="rounded-lg border border-amber-200 bg-amber-50 p-4 shadow-sm mb-3">
                      <div class="flex flex-wrap items-center justify-between gap-2">
                        <h4 class="text-sm font-semibold text-amber-800">Notion mismatches</h4>
                        <span class="text-xs text-amber-700">
                          {map_size(diffs)} difference{if map_size(diffs) == 1, do: "", else: "s"}
                        </span>
                      </div>
                      <div class="mt-3 overflow-x-auto">
                        <table class="min-w-full text-xs">
                          <thead>
                            <tr class="text-left text-amber-900">
                              <th class="px-2 py-1">Field</th>
                              <th class="px-2 py-1">Expected</th>
                              <th class="px-2 py-1">Actual</th>
                            </tr>
                          </thead>
                          <tbody class="text-amber-900">
                            <%= for {field, change} <- ordered_diff_list(diffs) do %>
                              <tr class="align-top">
                                <td class="px-2 py-1 whitespace-nowrap font-medium">
                                  {diff_field_label(field)}
                                </td>
                                <td class="px-2 py-1">
                                  {present_string(Map.get(change, :expected))}
                                </td>
                                <td class="px-2 py-1">{present_string(Map.get(change, :actual))}</td>
                              </tr>
                            <% end %>
                          </tbody>
                        </table>
                      </div>
                    </div>
                  <% end %>

                  <%= if @show_metadata_column? do %>
                    <%# Sync from Notion button — only shown when the trade has a known Notion page %>
                    <% trade_title = item_ticker(item) <> "@" <> item_datetime_value(item) %>
                    <% notion_page_id_for_row = Map.get(@page_ids_map || %{}, trade_title) %>
                    <%= if is_binary(notion_page_id_for_row) and not is_nil(@on_sync_metadata_event) do %>
                      <div class="flex justify-end mb-2">
                        <button
                          type="button"
                          phx-click={@on_sync_metadata_event}
                          phx-value-index={idx}
                          class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-emerald-700 bg-emerald-50 border border-emerald-200 rounded hover:bg-emerald-100 transition"
                        >
                          ↙ Sync from Notion
                        </button>
                      </div>
                    <% end %>
                    <.render_metadata_form
                      version={@global_metadata_version}
                      item={item}
                      idx={idx}
                      on_save_event={@on_save_metadata_event}
                      on_reset_event={@on_reset_metadata_event}
                      drafts={@drafts}
                      on_apply_draft_event={@on_apply_draft_event}
                    />
                  <% end %>

                  <%= if has_chain do %>
                    <div class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
                      <div class="flex flex-wrap items-center justify-between gap-2">
                        <h4 class="text-sm font-semibold text-slate-700">Action chain</h4>
                        <span class="text-xs text-slate-500">
                          {chain_length} {if chain_length == 1, do: "step", else: "steps"}
                        </span>
                      </div>
                      <ol class="mt-4 space-y-3">
                        <%= for {action, action_idx} <- Enum.with_index(chain) do %>
                          <% action_time = format_action_time(action) %>
                          <% action_meta = action_meta(action) %>
                          <% action_notes = action_notes(action) %>
                          <li class="relative">
                            <div class="grid grid-cols-[auto_1fr_auto] items-start gap-3">
                              <div class="relative">
                                <div class="z-10 inline-flex h-6 w-6 items-center justify-center rounded-full bg-blue-600 text-[11px] font-semibold text-white shadow">
                                  {action_idx + 1}
                                </div>
                                <div
                                  :if={action_idx < chain_length - 1}
                                  class="absolute left-1/2 top-6 -ml-px h-full w-px bg-slate-200"
                                >
                                </div>
                              </div>
                              <div class="rounded-md border border-slate-200 bg-slate-50 px-4 py-3">
                                <div class="flex flex-wrap items-center justify-between gap-2">
                                  <span class="text-sm font-medium text-slate-800">
                                    {action_label(action, action_idx)}
                                  </span>
                                  <span :if={action_time != ""} class="text-xs text-slate-500">
                                    {action_time}
                                  </span>
                                </div>
                                <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-slate-600">
                                  <div
                                    :if={action_price(action)}
                                    class="inline-flex items-center gap-1 font-medium text-slate-700"
                                  >
                                    <span class="text-slate-500">Price:</span>
                                    <span>{action_price(action)}</span>
                                  </div>
                                  <%= for meta <- action_meta do %>
                                    <span class="inline-flex items-center gap-1">
                                      <span class="h-1.5 w-1.5 rounded-full bg-slate-300"></span>
                                      {meta}
                                    </span>
                                  <% end %>
                                  <.link
                                    :if={
                                      action_id =
                                        Map.get(action, :activity_statement_id) ||
                                          Map.get(action, "activity_statement_id")
                                    }
                                    navigate={~p"/activity_statement/#{action_id}"}
                                    class="inline-flex items-center rounded border border-blue-200 px-2 py-0.5 text-[11px] font-medium text-blue-700 hover:bg-blue-50"
                                    title="View activity statement"
                                  >
                                    View statement →
                                  </.link>
                                </div>
                                <p
                                  :if={action_notes != ""}
                                  class="mt-2 text-xs leading-relaxed text-slate-600"
                                >
                                  {action_notes}
                                </p>
                              </div>
                              <div class="pt-1 text-right"></div>
                            </div>
                          </li>
                        <% end %>
                      </ol>
                    </div>
                  <% else %>
                    <div class="rounded-lg border border-dashed border-slate-300 bg-white p-4 text-sm text-slate-500">
                      No recorded actions for this trade.
                    </div>
                  <% end %>
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

  # Format duration in seconds to a human-readable string
  defp format_duration(nil), do: "-"
  defp format_duration(seconds) when is_integer(seconds) and seconds < 0, do: "-"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 ->
        "#{seconds}s"

      seconds < 3600 ->
        mins = div(seconds, 60)
        secs = rem(seconds, 60)
        if secs == 0, do: "#{mins}m", else: "#{mins}m #{secs}s"

      seconds < 86400 ->
        hours = div(seconds, 3600)
        mins = div(rem(seconds, 3600), 60)
        if mins == 0, do: "#{hours}h", else: "#{hours}h #{mins}m"

      true ->
        days = div(seconds, 86400)
        hours = div(rem(seconds, 86400), 3600)
        if hours == 0, do: "#{days}d", else: "#{days}d #{hours}h"
    end
  end

  defp format_duration(_), do: "-"

  # Sorting helpers
  defp sort_items(items, sort_by, sort_dir) when is_list(items) do
    dir = normalize_dir(sort_dir)
    key = normalize_key(sort_by)
    sorter = sorter_for(key)

    items
    |> Enum.sort_by(sorter, dir)
  end

  defp normalize_key(k) when k in [:date, :ticker, :side, :result, :duration, :pl], do: k

  defp normalize_key(k) when is_binary(k) do
    key =
      try do
        String.to_existing_atom(k)
      rescue
        ArgumentError -> :date
      end

    if key in [:date, :ticker, :side, :result, :duration, :pl], do: key, else: :date
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
  defp sorter_for(:duration), do: &(Map.get(&1, :duration) || 0)
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

  # Action chain helpers
  defp detail_colspan(assigns, show_toggle?) do
    # base columns: Date, Ticker, Side, Result, Duration, P/L
    base = 6
    # optional Page ID column
    base = if Map.get(assigns, :show_page_id_column?), do: base + 1, else: base
    # optional Mismatch column
    base = if Map.get(assigns, :show_inconsistency_column?), do: base + 1, else: base
    # optional Metadata column
    base = if Map.get(assigns, :show_metadata_column?), do: base + 1, else: base

    base = if show_toggle?, do: base + 1, else: base
    base = if Map.get(assigns, :selectable?), do: base + 1, else: base
    base = if Map.get(assigns, :show_save_controls?), do: base + 2, else: base

    base
  end

  # NOTE: visibility of the toggle is handled by assigns; presence is computed inline where needed

  defp action_chain(item, key) when is_map(item) do
    candidates =
      [key, :action_chain, :actions, :legs, "action_chain", "actions", "legs"]
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn
        value when is_atom(value) -> [value, Atom.to_string(value)]
        value when is_binary(value) -> [value]
        _ -> []
      end)

    candidates
    |> Enum.reduce_while([], fn candidate, acc ->
      case fetch_chain(item, candidate) do
        list when is_list(list) -> {:halt, Enum.reject(list, &is_nil/1)}
        map when is_map(map) -> {:halt, map_chain_to_list(map)}
        _ -> {:cont, acc}
      end
    end)
    |> case do
      [] -> []
      list -> list
    end
  end

  defp action_chain(_item, _key), do: []

  defp fetch_chain(item, key) when is_atom(key), do: Map.get(item, key)
  defp fetch_chain(item, key) when is_binary(key), do: Map.get(item, key)
  defp fetch_chain(_item, _key), do: nil

  defp action_label(action, idx) when is_map(action) do
    label_raw =
      action
      |> fetch_first([:label, "label", :title, "title", :action, "action"])

    label = format_action_text(label_raw)

    if label != "" do
      label
    else
      parts =
        [:type, :side, :verb]
        |> Enum.map(fn key ->
          action |> fetch_first([key, Atom.to_string(key)]) |> format_action_text()
        end)
        |> Enum.reject(&(&1 == ""))

      case parts do
        [] -> "Step #{idx + 1}"
        _ -> Enum.join(parts, " • ")
      end
    end
  end

  defp action_label(_action, idx), do: "Step #{idx + 1}"

  defp format_action_time(action) when is_map(action) do
    action
    |> fetch_first([
      :datetime,
      :timestamp,
      :executed_at,
      :filled_at,
      :time,
      "datetime",
      "timestamp",
      "executed_at",
      "filled_at",
      "time"
    ])
    |> format_time_value()
  end

  defp format_action_time(_), do: ""

  defp action_meta(action) when is_map(action) do
    [
      meta_segment(action, [:quantity, "quantity", :qty, "qty"], "Qty", decimals: 0),
      meta_segment(action, [:contracts, "contracts"], "Contracts", decimals: 0),
      meta_segment(
        action,
        [:avg_price, "avg_price", :average_price, "average_price"],
        "Avg Price"
      ),
      meta_segment(action, [:realized_pl, "realized_pl", :pl, "pl"], "P/L"),
      meta_segment(action, [:commission, "commission", :fee, "fee", :fees, "fees"], "Fees")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp action_meta(_), do: []

  defp action_notes(action) when is_map(action) do
    action
    |> fetch_first([:notes, "notes", :comment, "comment", :description, "description"])
    |> present_string()
  end

  defp action_notes(_), do: ""

  defp action_price(action) when is_map(action) do
    price = fetch_first(action, [:price, "price", :trade_price, "trade_price"])

    cond do
      is_nil(price) ->
        nil

      match?(%Decimal{}, price) ->
        format_meta_value(price, [])

      is_number(price) ->
        format_meta_value(price, [])

      is_binary(price) ->
        price
        |> String.trim()
        |> case do
          "" -> nil
          s -> s
        end

      true ->
        nil
    end
  end

  defp action_price(_), do: nil

  defp meta_segment(action, keys, label, opts \\ []) do
    action
    |> fetch_first(keys)
    |> format_meta_value(opts)
    |> case do
      nil -> nil
      value -> "#{label}: #{value}"
    end
  end

  defp format_meta_value(nil, _opts), do: nil

  defp format_meta_value(%Decimal{} = dec, opts),
    do: format_meta_value(Decimal.to_float(dec), opts)

  defp format_meta_value(value, opts) when is_number(value) do
    if is_integer(value) do
      Integer.to_string(value)
    else
      decimals = Keyword.get(opts, :decimals, 2)
      :erlang.float_to_binary(value * 1.0, [:compact, {:decimals, decimals}])
    end
  end

  defp format_meta_value(value, _opts) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp format_meta_value(value, _opts) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp format_meta_value(_value, _opts), do: nil

  defp format_time_value(nil), do: ""

  defp format_time_value(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_time_value(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M")
  end

  defp format_time_value(%Date{} = d) do
    Date.to_iso8601(d)
  end

  defp format_time_value(value) when is_binary(value) do
    String.trim(value)
  end

  defp format_time_value(_), do: ""

  defp fetch_first(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp present_string(nil), do: ""

  defp present_string(value) when is_binary(value) do
    value
    |> String.trim()
  end

  defp present_string(true), do: "Yes"
  defp present_string(false), do: "No"

  defp present_string(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp present_string(value) when is_number(value), do: to_string(value)
  defp present_string(%Decimal{} = dec), do: Decimal.to_string(dec)
  defp present_string(_), do: ""

  # Convert map-based chains like %{"1" => %{...}, "2" => %{...}} to a list ordered by numeric key
  defp map_chain_to_list(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {coerce_key_to_int(k), v} end)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.map(fn {_i, v} -> v end)
    |> Enum.reject(&is_nil/1)
  end

  defp coerce_key_to_int(k) when is_integer(k), do: k

  defp coerce_key_to_int(k) when is_binary(k) do
    case Integer.parse(k) do
      {i, _} -> i
      :error -> 9_223_372_036_854_775_807
    end
  end

  defp coerce_key_to_int(k) when is_atom(k), do: coerce_key_to_int(Atom.to_string(k))
  defp coerce_key_to_int(_), do: 9_223_372_036_854_775_807

  defp format_action_text(nil), do: ""

  defp format_action_text(v) when is_binary(v) do
    v
    |> String.trim()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp format_action_text(v) when is_atom(v) do
    v
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp format_action_text(v), do: present_string(v)

  # --- Diff helpers for mismatch display ---
  defp diffs_tooltip(diffs) when is_map(diffs) do
    diffs
    |> ordered_diff_list()
    |> Enum.map(fn {field, change} ->
      label = diff_field_label(field)
      exp = present_string(Map.get(change, :expected))
      act = present_string(Map.get(change, :actual))
      label <> ": " <> exp <> " → " <> act
    end)
    |> Enum.join("\n")
  end


  defp ordered_diff_list(diffs) when is_map(diffs) do
    order = [
      :title, :ticker, :side, :result, :realized_pl, :duration,
      :entry_timeslot, :close_timeslot,
      :rank, :setup, :close_trigger, :order_type,
      :done?, :lost_data?, :close_time_comment
    ]

    ordered =
      order
      |> Enum.flat_map(fn k ->
        if Map.has_key?(diffs, k), do: [{k, Map.fetch!(diffs, k)}], else: []
      end)

    remaining =
      diffs
      |> Map.drop(order)
      |> Enum.to_list()
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)

    ordered ++ remaining
  end


  defp diff_field_label(:title), do: "Title"
  defp diff_field_label(:datetime), do: "Datetime"
  defp diff_field_label(:ticker), do: "Ticker"
  defp diff_field_label(:side), do: "Side"
  defp diff_field_label(:result), do: "Result"
  defp diff_field_label(:realized_pl), do: "Realized P/L"
  defp diff_field_label(:duration), do: "Duration"
  defp diff_field_label(:entry_timeslot), do: "Entry timeslot"
  defp diff_field_label(:close_timeslot), do: "Close timeslot"
  defp diff_field_label(:close_time_comment), do: "Close time comment"
  defp diff_field_label(:close_trigger), do: "Close trigger"
  defp diff_field_label(:order_type), do: "Order type"
  defp diff_field_label(:fomo?), do: "FOMO?"
  defp diff_field_label(:initial_risk_reward_ratio), do: "Initial R:R"
  defp diff_field_label(:best_risk_reward_ratio), do: "Best R:R"
  defp diff_field_label(:slipped_position?), do: "Slipped position?"

  defp diff_field_label(other) when is_atom(other) do
    other
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp diff_field_label(other) when is_binary(other) do
    other
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp diff_field_label(_), do: "Field"

  # Smart metadata version badge that shows saved vs editing version
  attr :saved_version, :integer, default: nil
  attr :global_version, :integer, required: true
  attr :has_data, :boolean, required: true
  attr :is_done, :boolean, required: true

  defp metadata_version_badge(assigns) do
    ~H"""
    <%= cond do %>
      <%!-- Case 1: Has data, version matches, and done --%>
      <% @has_data and @saved_version == @global_version and @is_done -> %>
        <div class="inline-flex flex-col items-center gap-1" title="Saved and complete">
          <span class="inline-flex items-center px-2 py-0.5 bg-green-100 text-green-700 font-medium rounded">
            V{@saved_version} ✓
          </span>
          <span class="text-[10px] text-green-600 font-medium">Filled</span>
        </div>

      <%!-- Case 2: Has data, version matches, but not done --%>
      <% @has_data and @saved_version == @global_version and not @is_done -> %>
        <div class="inline-flex flex-col items-center gap-1" title="Saved but incomplete">
          <span class="inline-flex items-center px-2 py-0.5 bg-blue-100 text-blue-700 font-medium rounded">
            V{@saved_version}
          </span>
          <span class="text-[10px] text-gray-500">Pending</span>
        </div>

      <%!-- Case 3: No saved version - will save as global version --%>
      <% is_nil(@saved_version) or not @has_data -> %>
        <div class="inline-flex flex-col items-center gap-1" title={"Will save as V#{@global_version}"}>
          <span class="inline-flex items-center px-2 py-0.5 bg-gray-100 text-gray-600 font-medium rounded border border-dashed border-gray-300">
            V{@global_version}
          </span>
          <span class="text-[10px] text-gray-500">New</span>
        </div>

      <%!-- Case 4: Version mismatch - editing different version --%>
      <% @has_data and @saved_version != @global_version -> %>
        <div class="inline-flex flex-col items-center gap-1" title={"Saved as V#{@saved_version}, editing with V#{@global_version}"}>
          <div class="flex items-center gap-1">
            <span class="inline-flex items-center px-1.5 py-0.5 bg-amber-100 text-amber-700 text-[10px] font-medium rounded">
              V{@saved_version}
            </span>
            <span class="text-gray-400">→</span>
            <span class="inline-flex items-center px-1.5 py-0.5 bg-blue-100 text-blue-700 text-[10px] font-medium rounded">
              V{@global_version}
            </span>
          </div>
          <span class="text-[10px] text-amber-600">Converting</span>
        </div>
    <% end %>
    """
  end

  # Render appropriate metadata form based on version
  attr :version, :integer, required: true
  attr :item, :map, required: true
  attr :idx, :integer, required: true
  attr :on_save_event, :string, default: nil
  attr :on_reset_event, :string, default: nil
  attr :drafts, :list, default: []
  attr :on_apply_draft_event, :string, default: nil

  defp render_metadata_form(assigns) do
    ~H"""
    <%= case @version do %>
      <% 1 -> %>
        <JournalexWeb.MetadataForm.v1
          item={@item}
          idx={@idx}
          on_save_event={@on_save_event}
          on_reset_event={@on_reset_event}
          drafts={@drafts}
          on_apply_draft_event={@on_apply_draft_event}
        />
      <% 2 -> %>
        <JournalexWeb.MetadataForm.v2
          item={@item}
          idx={@idx}
          on_save_event={@on_save_event}
          on_reset_event={@on_reset_event}
          drafts={@drafts}
          on_apply_draft_event={@on_apply_draft_event}
        />
      <% _ -> %>
        <div class="rounded-lg border border-gray-200 bg-gray-50 p-4 text-center text-sm text-gray-500">
          Unsupported version: {@version}
        </div>
    <% end %>
    """
  end
end

defmodule JournalexWeb.MetadataForm do
  @moduledoc """
  Reusable metadata form components for V1 and V2 trade metadata editing.
  """

  use JournalexWeb, :html

  @doc """
  Renders a V1 metadata form (original Notion DB structure).
  """
  attr :item, :map, required: true
  attr :idx, :integer, required: true
  attr :on_save_event, :string, required: true
  attr :on_reset_event, :string, default: nil
  attr :drafts, :list, default: []
  attr :on_apply_draft_event, :string, default: nil
  attr :draft_name, :string, default: ""
  attr :save_label, :string, default: "Save Metadata"
  attr :on_change_event, :string, default: nil

  def v1(assigns) do
    ~H"""
    <div class="rounded-lg border border-indigo-200 bg-indigo-50 p-4 shadow-sm mb-3">
      <div class="flex items-start justify-between gap-2 mb-3">
        <h4 class="text-sm font-semibold text-indigo-800">Trade Metadata (V1)</h4>
        <div :if={@on_apply_draft_event && @drafts != []} class="flex flex-wrap justify-end gap-1.5">
          <%= for draft <- @drafts do %>
            <button
              type="button"
              phx-click={@on_apply_draft_event}
              phx-value-draft-id={draft.id}
              phx-value-index={@idx}
              class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-amber-100 text-amber-800 border border-amber-200 hover:bg-amber-200 transition cursor-pointer"
              title={"Apply draft: #{draft.name}"}
            >
              {draft.name}
            </button>
          <% end %>
        </div>
      </div>

      <form phx-submit={@on_save_event} phx-change={@on_change_event} phx-value-index={@idx} class="space-y-4">
        <input type="hidden" id={"hidden-draft-name-#{@idx}"} name="draft_name" value={@draft_name} />
        <% metadata = Map.get(@item, :metadata) || %{} %>

        <div class="flex flex-wrap gap-1.5">
          <!-- Done pill -->
          <label class="cursor-pointer">
            <input type="checkbox" name="done" value="true" checked={Map.get(metadata, :done?) || Map.get(metadata, "done?")} class="sr-only peer" />
            <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-indigo-600 peer-checked:text-white peer-checked:border-indigo-600 transition">Done</span>
          </label>
          <!-- Lost Data pill -->
          <label class="cursor-pointer">
            <input type="checkbox" name="lost_data" value="true" checked={Map.get(metadata, :lost_data?) || Map.get(metadata, "lost_data?")} class="sr-only peer" />
            <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-indigo-600 peer-checked:text-white peer-checked:border-indigo-600 transition">Lost Data</span>
          </label>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <!-- Rank radio -->
          <div class="col-span-full">
            <span class="block text-sm font-medium text-gray-700 mb-1">Rank</span>
            <div class="flex flex-wrap gap-1.5">
              <label class="cursor-pointer">
                <input type="radio" name="rank" value="" checked={(Map.get(metadata, :rank) || Map.get(metadata, "rank")) in [nil, ""]} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">
                  None
                </span>
              </label>
              <%= for rank_val <- v1_rank_options() do %>
                <label class="cursor-pointer">
                  <input type="radio" name="rank" value={rank_val} checked={Map.get(metadata, :rank) == rank_val || Map.get(metadata, "rank") == rank_val} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-indigo-600 peer-checked:text-white peer-checked:border-indigo-600 transition">
                    {rank_val}
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <!-- Setup select -->
          <div>
            <label for={"setup_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Setup
            </label>
            <select
              name="setup"
              id={"setup_#{@idx}"}
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            >
              <option value="">Select setup...</option>
              <%= for opt <- v1_setup_options() do %>
                <option value={opt} selected={Map.get(metadata, :setup) == opt || Map.get(metadata, "setup") == opt}>
                  {opt}
                </option>
              <% end %>
            </select>
          </div>

          <!-- Close Trigger radio -->
          <div class="col-span-full">
            <span class="block text-sm font-medium text-gray-700 mb-1">Close Trigger</span>
            <div class="flex flex-wrap gap-1.5">
              <label class="cursor-pointer">
                <input type="radio" name="close_trigger" value="" checked={(Map.get(metadata, :close_trigger) || Map.get(metadata, "close_trigger")) in [nil, ""]} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">
                  None
                </span>
              </label>
              <%= for opt <- close_trigger_options() do %>
                <label class="cursor-pointer">
                  <input type="radio" name="close_trigger" value={opt} checked={Map.get(metadata, :close_trigger) == opt || Map.get(metadata, "close_trigger") == opt} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-indigo-600 peer-checked:text-white peer-checked:border-indigo-600 transition">
                    {opt}
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <!-- Sector (read-only rollup from TickerLink) -->
          <div>
            <label for={"sector_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Sector <span class="text-xs text-gray-400">(rollup)</span>
            </label>
            <input
              type="text"
              id={"sector_#{@idx}"}
              value={Map.get(metadata, :sector) || Map.get(metadata, "sector")}
              placeholder="Populated via TickerLink"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>

          <!-- Cap Size (read-only rollup from TickerLink) -->
          <div>
            <label for={"cap_size_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Cap Size <span class="text-xs text-gray-400">(rollup)</span>
            </label>
            <input
              type="text"
              id={"cap_size_#{@idx}"}
              value={Map.get(metadata, :cap_size) || Map.get(metadata, "cap_size")}
              placeholder="Populated via TickerLink"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>

          <!-- Entry Timeslot (read-only, auto-calculated from action chain) -->
          <div>
            <label for={"entry_timeslot_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Entry Timeslot <span class="text-xs text-gray-400">(auto)</span>
            </label>
            <input
              type="text"
              id={"entry_timeslot_#{@idx}"}
              value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot") || Journalex.Notion.compute_entry_timeslot(@item)}
              placeholder="Auto-calculated from trade data"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>
        </div>

        <!-- Trade Characteristics -->
        <div>
          <h5 class="text-sm font-medium text-gray-700 mb-2">Trade Characteristics</h5>
          <div class="space-y-2">
            <%= for {group_label, flags} <- v1_flag_groups() do %>
              <div class="rounded border border-indigo-100 bg-white px-3 py-2">
                <span class="block text-xs font-semibold uppercase tracking-wide text-indigo-400 mb-1.5">{group_label}</span>
                <div class="flex flex-wrap gap-1.5">
                  <%= for {flag_name, label} <- flags do %>
                    <label class="cursor-pointer">
                      <input type="checkbox" name={flag_name} value="true" checked={Map.get(metadata, String.to_atom(flag_name <> "?")) || Map.get(metadata, flag_name <> "?")} class="sr-only peer" />
                      <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-indigo-600 peer-checked:text-white peer-checked:border-indigo-600 transition">{label}</span>
                    </label>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Close Time Comment (multi-select) -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Close Time Comment</label>
          <div class="flex flex-wrap gap-1.5">
            <%= for option <- close_time_comment_options() do %>
              <label class="cursor-pointer">
                <input type="checkbox" name="close_time_comment[]" value={option} checked={option in parse_close_time_comments(metadata)} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-indigo-600 peer-checked:text-white peer-checked:border-indigo-600 transition">{option}</span>
              </label>
            <% end %>
          </div>
        </div>

        <!-- Action buttons -->
        <div class="flex justify-end space-x-2 pt-2 border-t border-indigo-200">
          <button
            :if={not is_nil(@on_reset_event)}
            type="button"
            phx-click={@on_reset_event}
            phx-value-index={@idx}
            class="inline-flex items-center px-4 py-2 bg-white text-gray-700 text-sm font-medium rounded border border-gray-300 hover:bg-gray-50 transition"
            data-confirm="Clear all metadata for this trade?"
          >
            Reset
          </button>
          <button
            type="submit"
            class="inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded hover:bg-indigo-700 transition"
          >
            {@save_label}
          </button>
        </div>
      </form>
    </div>
    """
  end

  @doc """
  Renders a V2 metadata form (enhanced Notion DB structure).
  """
  attr :item, :map, required: true
  attr :idx, :integer, required: true
  attr :on_save_event, :string, required: true
  attr :on_reset_event, :string, default: nil
  attr :drafts, :list, default: []
  attr :on_apply_draft_event, :string, default: nil
  attr :draft_name, :string, default: ""
  attr :save_label, :string, default: "Save Metadata"
  attr :on_change_event, :string, default: nil
  attr :r_size, :float, default: nil

  def v2(assigns) do
    ~H"""
    <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 shadow-sm mb-3">
      <div class="flex items-start justify-between gap-2 mb-3">
        <h4 class="text-sm font-semibold text-blue-800">Trade Metadata (V2)</h4>
        <div :if={@on_apply_draft_event && @drafts != []} class="flex flex-wrap justify-end gap-1.5">
          <%= for draft <- @drafts do %>
            <button
              type="button"
              phx-click={@on_apply_draft_event}
              phx-value-draft-id={draft.id}
              phx-value-index={@idx}
              class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-amber-100 text-amber-800 border border-amber-200 hover:bg-amber-200 transition cursor-pointer"
              title={"Apply draft: #{draft.name}"}
            >
              {draft.name}
            </button>
          <% end %>
        </div>
      </div>

      <form phx-submit={@on_save_event} phx-change={@on_change_event} phx-value-index={@idx} class="space-y-4">
        <input type="hidden" id={"hidden-draft-name-#{@idx}"} name="draft_name" value={@draft_name} />
        <% metadata = Map.get(@item, :metadata) || %{} %>

        <div class="flex flex-wrap gap-1.5">
          <!-- Done pill -->
          <label class="cursor-pointer">
            <input type="checkbox" name="done" value="true" checked={Map.get(metadata, :done?) || Map.get(metadata, "done?")} class="sr-only peer" />
            <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">Done</span>
          </label>
          <!-- Lost Data pill -->
          <label class="cursor-pointer">
            <input type="checkbox" name="lost_data" value="true" checked={Map.get(metadata, :lost_data?) || Map.get(metadata, "lost_data?")} class="sr-only peer" />
            <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">Lost Data</span>
          </label>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <!-- Rank radio -->
          <div class="col-span-full">
            <span class="block text-sm font-medium text-gray-700 mb-1">Rank</span>
            <div class="flex flex-wrap gap-1.5">
              <label class="cursor-pointer">
                <input type="radio" name="rank" value="" checked={(Map.get(metadata, :rank) || Map.get(metadata, "rank")) in [nil, ""]} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">
                  None
                </span>
              </label>
              <%= for rank_val <- v2_rank_options() do %>
                <label class="cursor-pointer">
                  <input type="radio" name="rank" value={rank_val} checked={Map.get(metadata, :rank) == rank_val || Map.get(metadata, "rank") == rank_val} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">
                    {rank_val}
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <!-- Setup select -->
          <div>
            <label for={"setup_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Setup
            </label>
            <select
              name="setup"
              id={"setup_#{@idx}"}
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            >
              <option value="">Select setup...</option>
              <%= for opt <- v2_setup_options() do %>
                <option value={opt} selected={Map.get(metadata, :setup) == opt || Map.get(metadata, "setup") == opt}>
                  {opt}
                </option>
              <% end %>
            </select>
          </div>

          <!-- Close Trigger radio -->
          <div class="col-span-full">
            <span class="block text-sm font-medium text-gray-700 mb-1">Close Trigger</span>
            <div class="flex flex-wrap gap-1.5">
              <label class="cursor-pointer">
                <input type="radio" name="close_trigger" value="" checked={(Map.get(metadata, :close_trigger) || Map.get(metadata, "close_trigger")) in [nil, ""]} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">
                  None
                </span>
              </label>
              <%= for opt <- close_trigger_options() do %>
                <label class="cursor-pointer">
                  <input type="radio" name="close_trigger" value={opt} checked={Map.get(metadata, :close_trigger) == opt || Map.get(metadata, "close_trigger") == opt} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">
                    {opt}
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <!-- Sector (read-only rollup from TickerLink) -->
          <div>
            <label for={"sector_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Sector <span class="text-xs text-gray-400">(rollup)</span>
            </label>
            <input
              type="text"
              id={"sector_#{@idx}"}
              value={Map.get(metadata, :sector) || Map.get(metadata, "sector")}
              placeholder="Populated via TickerLink"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>

          <!-- Cap Size (read-only rollup from TickerLink) -->
          <div>
            <label for={"cap_size_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Cap Size <span class="text-xs text-gray-400">(rollup)</span>
            </label>
            <input
              type="text"
              id={"cap_size_#{@idx}"}
              value={Map.get(metadata, :cap_size) || Map.get(metadata, "cap_size")}
              placeholder="Populated via TickerLink"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>

          <!-- Order Type radio -->
          <div class="col-span-full">
            <span class="block text-sm font-medium text-gray-700 mb-1">Order Type</span>
            <div class="flex flex-wrap gap-1.5">
              <label class="cursor-pointer">
                <input type="radio" name="order_type" value="" checked={(Map.get(metadata, :order_type) || Map.get(metadata, "order_type")) in [nil, ""]} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">
                  None
                </span>
              </label>
              <%= for opt <- order_type_options() do %>
                <label class="cursor-pointer">
                  <input type="radio" name="order_type" value={opt} checked={Map.get(metadata, :order_type) == opt || Map.get(metadata, "order_type") == opt} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">
                    {opt}
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <!-- R:R Ratios & Size sliders -->
          <div class="col-span-full">
            <span class="block text-sm font-medium text-gray-700 mb-2">R:R &amp; Size</span>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-3">

              <!-- Initial R:R -->
              <div id={"rr_initial_#{@idx}"} phx-hook="RangeNumberSync">
                <label class="block text-xs text-gray-600 mb-1">Initial R:R</label>
                <div class="flex items-center gap-2">
                  <input type="range" min="0" max="20" step="0.01"
                    value={format_decimal(Map.get(metadata, :initial_risk_reward_ratio) || Map.get(metadata, "initial_risk_reward_ratio"))}
                    class="flex-1 accent-blue-600 cursor-pointer" />
                  <input type="number" name="initial_risk_reward_ratio" min="0" step="0.01"
                    value={format_decimal(Map.get(metadata, :initial_risk_reward_ratio) || Map.get(metadata, "initial_risk_reward_ratio"))}
                    class="w-20 px-2 py-1 text-sm border border-gray-300 rounded-md text-right focus:ring-blue-500 focus:border-blue-500" />
                </div>
              </div>

              <!-- Best R:R -->
              <% best_rr_raw = Map.get(metadata, :best_risk_reward_ratio) || Map.get(metadata, "best_risk_reward_ratio") %>
              <% best_rr_on = best_rr_enabled?(best_rr_raw) %>
              <div>
                <div class="flex items-center gap-2 mb-1">
                  <label class="block text-xs text-gray-600">Best R:R</label>
                  <label class="cursor-pointer" title="Only applies on win trades">
                    <input
                      type="checkbox"
                      name="best_rr_enabled"
                      value="true"
                      checked={best_rr_on}
                      class="sr-only peer"
                      onchange={"document.getElementById('rr_best_#{@idx}').classList.toggle('hidden', !this.checked)"}
                    />
                    <span class="inline-block border rounded-full px-2 py-0.5 text-xs transition border-gray-300 text-gray-500 peer-checked:bg-green-600 peer-checked:text-white peer-checked:border-green-600">
                      Win
                    </span>
                  </label>
                </div>
                <div id={"rr_best_#{@idx}"} phx-hook="RangeNumberSync" class={if best_rr_on, do: "", else: "hidden"}>
                  <div class="flex items-center gap-2">
                    <input type="range" min="0" max="20" step="0.01"
                      value={format_decimal(best_rr_raw, "0")}
                      class="flex-1 accent-blue-600 cursor-pointer" />
                    <input type="number" name="best_risk_reward_ratio" min="0" step="0.01"
                      value={format_decimal(best_rr_raw, "0")}
                      class="w-20 px-2 py-1 text-sm border border-gray-300 rounded-md text-right focus:ring-blue-500 focus:border-blue-500" />
                  </div>
                </div>
              </div>

              <!-- Size (plain number; auto-fills for losing trades) -->
              <% r_size = @r_size || Journalex.Settings.get_r_size() %>
              <% size_val = compute_size_value(@item, metadata, r_size) %>
              <% size_auto? = is_auto_size?(@item, metadata) %>
              <div>
                <label class="block text-xs text-gray-600 mb-1">Size</label>
                <input
                  type="number"
                  name="size"
                  min="0"
                  step="0.01"
                  value={format_decimal(size_val, "")}
                  placeholder={if size_auto?, do: "", else: "Enter size..."}
                  class={[
                    "w-full px-3 py-1 text-sm border rounded-md text-left focus:ring-blue-500 focus:border-blue-500",
                    if(size_auto?, do: "border-blue-300 bg-blue-50 text-blue-800", else: "border-gray-300")
                  ]}
                />
                <div :if={size_auto?} class="mt-1 flex items-center gap-1.5 rounded-md bg-blue-100 border border-blue-200 px-2 py-1">
                  <span class="text-blue-500 text-xs">&#9889;</span>
                  <span class="text-xs text-blue-700 font-medium">Auto-filled:</span>
                  <span class="text-xs text-blue-600 font-mono">{auto_size_hint(@item, r_size, size_val)}</span>
                </div>
              </div>

            </div>
          </div>

          <!-- Entry Timeslot (read-only, auto-calculated from action chain) -->
          <div>
            <label for={"entry_timeslot_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Entry Timeslot <span class="text-xs text-gray-400">(auto)</span>
            </label>
            <input
              type="text"
              id={"entry_timeslot_#{@idx}"}
              value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot") || Journalex.Notion.compute_entry_timeslot(@item)}
              placeholder="Auto-calculated from trade data"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>

          <!-- Close Timeslot (read-only, auto-calculated from action chain) -->
          <div>
            <label for={"close_timeslot_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Close Timeslot <span class="text-xs text-gray-400">(auto)</span>
            </label>
            <input
              type="text"
              id={"close_timeslot_#{@idx}"}
              value={Map.get(metadata, :close_timeslot) || Map.get(metadata, "close_timeslot") || Journalex.Notion.compute_close_timeslot(@item)}
              placeholder="Auto-calculated from trade data"
              disabled
              class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed"
            />
          </div>
        </div>

        <!-- Trade Analysis Flags -->
        <div>
          <h5 class="text-sm font-medium text-gray-700 mb-2">Trade Analysis</h5>
          <div class="space-y-2">
            <%= for {group_label, flags} <- v2_flag_groups() do %>
              <div class="rounded border border-blue-100 bg-white px-3 py-2">
                <span class="block text-xs font-semibold uppercase tracking-wide text-blue-400 mb-1.5">{group_label}</span>
                <div class="flex flex-wrap gap-1.5">
                  <%= for {flag_name, label} <- flags do %>
                    <label class="cursor-pointer">
                      <input type="checkbox" name={flag_name} value="true" checked={Map.get(metadata, String.to_atom(flag_name <> "?")) || Map.get(metadata, flag_name <> "?")} class="sr-only peer" />
                      <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">{label}</span>
                    </label>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Close Time Comment (multi-select) -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Close Time Comment</label>
          <div class="flex flex-wrap gap-1.5">
            <%= for option <- close_time_comment_options() do %>
              <label class="cursor-pointer">
                <input type="checkbox" name="close_time_comment[]" value={option} checked={option in parse_close_time_comments(metadata)} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-blue-600 peer-checked:text-white peer-checked:border-blue-600 transition">{option}</span>
              </label>
            <% end %>
          </div>
        </div>

        <!-- Action buttons -->
        <div class="flex justify-end space-x-2 pt-2 border-t border-blue-200">
          <button
            :if={not is_nil(@on_reset_event)}
            type="button"
            phx-click={@on_reset_event}
            phx-value-index={@idx}
            class="inline-flex items-center px-4 py-2 bg-white text-gray-700 text-sm font-medium rounded border border-gray-300 hover:bg-gray-50 transition"
            data-confirm="Clear all metadata for this trade?"
          >
            Reset
          </button>
          <button
            type="submit"
            class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded hover:bg-blue-700 transition"
          >
            {@save_label}
          </button>
        </div>
      </form>
    </div>
    """
  end

  # --- Option lists matching Notion select/multi_select fields ---

  defp v1_rank_options, do: ["BAD Trade", "C Trade", "B Trade", "A Trade"]
  defp v2_rank_options, do: ["Bad Setup", "Not Setup", "C Trade", "B Trade", "A Trade"]

  defp v1_setup_options do
    [
      "Trend Continuation - MACD",
      "Reversal - Double Top/Bottom",
      "Reversal - Double Top/Bottom - Pullback Reversal",
      "Reversal - Gravestone Doji",
      "Reversal - Exhausted Pressure",
      "Reversal - Three inside down",
      "Reversal - Day High/Low",
      "Breakout - Day High/Low",
      "Bouncy Ball - Big Seller/Buyer",
      "Not Setup"
    ]
  end

  defp v2_setup_options do
    [
      "Reversal - Double Top/Bottom",
      "Reversal - Double Top/Bottom - Sharp Top/Round Top",
      "Reversal - Pullback Reversal",
      "Reversal - Pullback Reversal - Gravestone Doji",
      "Reversal - Pullback Reversal - Three inside down",
      "Reversal - Weak Trend Reversal - Consolidation Below Top Liquidity Grab",
      "Reversal - Weak Trend Reversal - Spike Volume Extended Trend",
      "Reversal - Premarket Range Liquidity Grab",
      "Reversal - Capitulation",
      "Reversal - Day High/Low",
      "Breakout - Day High/Low",
      "Bouncy Ball - Big Seller/Buyer",
      "Trend Continuation - MACD",
      "Not Setup"
    ]
  end

  defp close_trigger_options do
    [
      "Automatically - Breakeven",
      "Automatically - Take Profit",
      "Automatically - Stop Loss",
      "Manually - Take Profit",
      "Manually - Stop Loss",
      "Manually - Reverse"
    ]
  end

  defp order_type_options do
    [
      "Limit Order",
      "Stop Order",
      "Market Order"
    ]
  end

  # entry_timeslot_options/0 removed — unused. Recoverable from git.

  defp close_time_comment_options do
    [
      "Will hit take profit if not close",
      "Will hit stop loss if not close",
      "Good close",
      "Should manually close earlier",
      "Too late",
      "Too early",
      "Admit failure",
      "Good close to lock profit",
      "Dangerous play",
      "Adjusted stop loss"
    ]
  end

  # Parse comma-separated close_time_comment string into a list for checkbox matching
  defp parse_close_time_comments(metadata) do
    raw = Map.get(metadata, :close_time_comment) || Map.get(metadata, "close_time_comment") || ""
    raw |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  # Convert option string to a safe HTML id fragment
  # option_id/1 removed — unused. Recoverable from git.

  # V1 metadata characteristic flags — grouped by theme
  defp v1_flag_groups do
    [
      {"Discipline", [
        {"follow_setup", "Follow Setup"},
        {"follow_stop_loss_management", "Follow SL Management"}
      ]},
      {"Psychology", [
        {"revenge_trade", "Revenge Trade"},
        {"fomo", "FOMO"},
        {"unnecessary_trade", "Unnecessary Trade"}
      ]},
      {"Execution", [
        {"operation_mistake", "Operation Mistake"}
      ]}
    ]
  end
  # Format a Decimal / float / binary field to a 2-decimal string for number inputs.
  # Defaults to "1.00" when the value is nil.
  defp best_rr_enabled?(nil), do: false
  defp best_rr_enabled?(%Decimal{} = d), do: Decimal.compare(d, Decimal.new("0")) == :gt
  defp best_rr_enabled?(n) when is_number(n), do: n > 0
  defp best_rr_enabled?(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f > 0
      :error -> false
    end
  end
  defp best_rr_enabled?(_), do: false

  defp format_decimal(nil), do: "1.00"
  defp format_decimal(%Decimal{} = d) do
    f = Decimal.to_float(d)
    :erlang.float_to_binary(f, [{:decimals, 2}])
  end
  defp format_decimal(val) do
    case Float.parse(to_string(val)) do
      {f, _} -> :erlang.float_to_binary(f, [{:decimals, 2}])
      :error  -> "1.00"
    end
  end

  # 2-arity variant — pass a custom fallback for nil (e.g. "" for optional fields).
  defp format_decimal(nil, default), do: default
  defp format_decimal(val, _default), do: format_decimal(val)

  # Display r_size without unnecessary ".0" suffix.
  defp format_r_size(r) when is_float(r) do
    if r == trunc(r), do: Integer.to_string(trunc(r)), else: Float.to_string(r)
  end
  defp format_r_size(r), do: to_string(r)

  # Auto-compute size for losing trades: |realized_pl| / r_size.
  # Returns existing size if already set, computed Decimal for losses, nil otherwise.
  defp compute_size_value(item, metadata, r_size) do
    existing = Map.get(metadata, :size) || Map.get(metadata, "size")
    if not is_nil(existing) do
      existing
    else
      result = Map.get(item, :result) || Map.get(item, "result")
      realized = Map.get(item, :realized_pl) || Map.get(item, "realized_pl")
      if result == "LOSE" and not is_nil(realized) and r_size > 0 do
        pl = to_pl_float(realized)
        computed = Float.round(abs(pl) / r_size, 2)
        if computed > 0, do: Decimal.from_float(computed), else: nil
      else
        nil
      end
    end
  end

  # Returns true when size will be auto-computed (no existing value, trade is a loss).
  defp is_auto_size?(item, metadata) do
    is_nil(Map.get(metadata, :size)) and
      is_nil(Map.get(metadata, "size")) and
      (Map.get(item, :result) || Map.get(item, "result")) == "LOSE"
  end

  defp to_pl_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_pl_float(n) when is_number(n), do: n * 1.0
  defp to_pl_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error  -> 0.0
    end
  end
  defp to_pl_float(_), do: 0.0

  # Builds a human-readable auto-fill formula for the Size hint strip.
  # Example output: "|$80.00| ÷ 8 = 10.00"
  defp auto_size_hint(item, r_size, size_val) do
    realized = Map.get(item, :realized_pl) || Map.get(item, "realized_pl")
    pl = abs(to_pl_float(realized))
    pl_str   = :erlang.float_to_binary(pl, [{:decimals, 2}])
    r_str    = format_r_size(r_size)
    size_str = format_decimal(size_val, "?")
    "|$#{pl_str}| ÷ #{r_str} = #{size_str}"
  end
  # V2 metadata analysis flags — grouped by theme
  defp v2_flag_groups do
    [
      {"Setup Context", [
        {"align_with_trend", "Align w/ Trend"},
        {"big_picture", "Big Picture"},
        {"hot_sector", "Hot Sector"},
        {"momentum", "Momentum"},
        {"news", "News"},
        {"earning_report", "Earning Report"},
        {"choppychart", "Choppy Chart"},
        {"mid_range", "Mid Range"}
      ]},
      {"Execution", [
        {"adjusted_risk_reward", "Adjusted R:R"},
        {"add_size", "Add Size"},
        {"follow_up_trial", "Follow Up Trial"},
        {"slipped_position", "Slipped Position"},
        {"operation_mistake", "Operation Mistake"}
      ]},
      {"Reflection", [
        {"normal_emotion", "Normal Emotion"},
        {"good_lesson", "Good Lesson"},
        {"better_risk_reward_ratio", "Better R:R"},
        {"close_trade_remorse", "Close Trade Remorse"}
      ]},
      {"Discipline", [
        {"revenge_trade", "Revenge Trade"},
        {"fomo", "FOMO"},
        {"overnight", "Overnight"},
        {"overnight_in_purpose", "Overnight in Purpose"}
      ]},
      {"Setup Review", [
        {"no_luck", "No Luck"},
        {"no_risk", "No Risk"},
        {"clear_liquidity_grab", "Clear Liquidity Grab"},
        {"entry_after_liquidity_grab", "Entry After Liquidity Grab"},
        {"instant_lose", "Instant Lose"},
        {"too_tight_stop_loss", "Too Tight Stop Loss"},
        {"affected_by_other_trade", "Affected by Other Trade"},
        {"fully_wrong_direction", "Fully Wrong Direction"}
      ]}
    ]
  end

  # ─── V3 component ────────────────────────────────────────────────────────

  @doc """
  Renders a V3 metadata form (redesigned Notion DB structure).
  Two sections: Notion Metadata (synced fields) and App Journal (progression chain).
  """
  attr :item, :map, required: true
  attr :idx, :integer, required: true
  attr :on_save_event, :string, required: true
  attr :on_reset_event, :string, default: nil
  attr :drafts, :list, default: []
  attr :on_apply_draft_event, :string, default: nil
  attr :draft_name, :string, default: ""
  attr :save_label, :string, default: "Save Metadata"
  attr :on_change_event, :string, default: nil
  attr :r_size, :float, default: nil
  attr :journal_data, :map, default: %{}
  attr :on_recalculate_size_event, :string, default: nil

  def v3(assigns) do
    ~H"""
    <div class="rounded-lg border border-violet-200 bg-violet-50 p-4 shadow-sm mb-3">
      <div class="flex items-start justify-between gap-2 mb-3">
        <h4 class="text-sm font-semibold text-violet-800">Trade Journal (V3)</h4>
        <div :if={@on_apply_draft_event && @drafts != []} class="flex flex-wrap justify-end gap-1.5">
          <%= for draft <- @drafts do %>
            <button
              type="button"
              phx-click={@on_apply_draft_event}
              phx-value-draft-id={draft.id}
              phx-value-index={@idx}
              class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-amber-100 text-amber-800 border border-amber-200 hover:bg-amber-200 transition cursor-pointer"
              title={"Apply draft: #{draft.name}"}
            >
              {draft.name}
            </button>
          <% end %>
        </div>
      </div>

      <%!-- ── NOTION METADATA section ── --%>
      <form phx-submit={@on_save_event} phx-change={@on_change_event} phx-value-index={@idx} class="space-y-4">
        <input type="hidden" id={"hidden-draft-name-#{@idx}"} name="draft_name" value={@draft_name} />
        <% metadata = Map.get(@item, :metadata) || %{} %>

        <p class="text-xs font-semibold uppercase tracking-wide text-violet-400">Notion Metadata</p>

        <%!-- ── PRE-TRADE zone (fill before / during trade) ── --%>
        <div class="rounded-lg border border-sky-200 bg-sky-50 p-3 space-y-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-sky-500">Pre-Trade</p>
          <%!-- Trade Nature sub-group --%>
          <% {_, trade_nature_flags} = Enum.find(v3_flag_groups(), fn {name, _} -> name == "Trade Nature" end) %>
          <div class="rounded border border-sky-100 bg-white px-3 py-2">
            <span class="block text-xs font-semibold uppercase tracking-wide text-sky-400 mb-1.5">Trade Nature</span>
            <div class="flex flex-wrap gap-1.5">
              <%= for {flag_name, label} <- trade_nature_flags do %>
                <label class="cursor-pointer">
                  <input type="checkbox" name={flag_name} value="true" checked={Map.get(metadata, String.to_atom(flag_name <> "?")) || Map.get(metadata, flag_name <> "?")} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-sky-600 peer-checked:text-white peer-checked:border-sky-600 transition">{label}</span>
                </label>
              <% end %>
            </div>
          </div>

          <%!-- Setup + Order Type --%>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label for={"setup_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">Setup</label>
              <select name="setup" id={"setup_#{@idx}"} class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-sky-500 focus:border-sky-500">
                <option value="">Select setup...</option>
                <%= for opt <- v3_setup_options() do %>
                  <option value={opt} selected={Map.get(metadata, :setup) == opt || Map.get(metadata, "setup") == opt}>{opt}</option>
                <% end %>
              </select>
            </div>
            <div>
              <div class="flex items-center gap-2 mb-1">
                <span class="text-sm font-medium text-gray-700">Order Type</span>
                <label class="cursor-pointer">
                  <input type="checkbox" name="use_draft_order" value="true" checked={Map.get(metadata, :use_draft_order?) || Map.get(metadata, "use_draft_order?")} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-sky-600 peer-checked:text-white peer-checked:border-sky-600 transition">Use Draft Order</span>
                </label>
              </div>
              <div class="flex flex-wrap gap-1.5">
                <label class="cursor-pointer">
                  <input type="radio" name="order_type" value="" checked={(Map.get(metadata, :order_type) || Map.get(metadata, "order_type")) in [nil, ""]} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">None</span>
                </label>
                <%= for opt <- order_type_options() do %>
                  <label class="cursor-pointer">
                    <input type="radio" name="order_type" value={opt} checked={Map.get(metadata, :order_type) == opt || Map.get(metadata, "order_type") == opt} class="sr-only peer" />
                    <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-sky-600 peer-checked:text-white peer-checked:border-sky-600 transition">{opt}</span>
                  </label>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Setup Context flags --%>
          <% {_, setup_ctx_flags} = Enum.find(v3_flag_groups(), fn {name, _} -> name == "Setup Context" end) %>
          <div class="rounded border border-sky-100 bg-white px-3 py-2">
            <span class="block text-xs font-semibold uppercase tracking-wide text-sky-400 mb-1.5">Setup Context</span>
            <div class="flex flex-wrap gap-1.5">
              <%= for {flag_name, label} <- setup_ctx_flags do %>
                <label class="cursor-pointer">
                  <input type="checkbox" name={flag_name} value="true" checked={Map.get(metadata, String.to_atom(flag_name <> "?")) || Map.get(metadata, flag_name <> "?")} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-sky-600 peer-checked:text-white peer-checked:border-sky-600 transition">{label}</span>
                </label>
              <% end %>
            </div>
          </div>

          <%!-- Patterns (multi-select, grouped) --%>
          <% patterns_selected = parse_multi_select(metadata, :patterns) %>
          <% patterns_known = Enum.flat_map(v3_patterns_options(), fn {_, opts} -> opts end) %>
          <% patterns_extra = Enum.reject(patterns_selected, &(&1 in patterns_known)) %>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1.5">Patterns</label>
            <div class="space-y-1.5">
              <%= for {group_label, options} <- v3_patterns_options() do %>
                <div>
                  <span class="block text-xs font-medium text-sky-500 mb-1">{group_label}</span>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for option <- options do %>
                      <label class="cursor-pointer">
                        <input type="checkbox" name="patterns[]" value={option} checked={option in patterns_selected} class="sr-only peer" />
                        <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-sky-600 peer-checked:text-white peer-checked:border-sky-600 transition">{option}</span>
                      </label>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <%!-- Overflow: any saved values synced from Notion not in known groups --%>
              <div :if={patterns_extra != []}>
                <span class="block text-xs font-medium text-sky-400 mb-1">Other (synced)</span>
                <div class="flex flex-wrap gap-1.5">
                  <%= for option <- patterns_extra do %>
                    <label class="cursor-pointer">
                      <input type="checkbox" name="patterns[]" value={option} checked={option in patterns_selected} class="sr-only peer" />
                      <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-sky-600 peer-checked:text-white peer-checked:border-sky-600 transition">{option}</span>
                    </label>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- ── Divider ── --%>
        <div class="relative">
          <div class="absolute inset-0 flex items-center" aria-hidden="true">
            <div class="w-full border-t border-dashed border-violet-300"></div>
          </div>
          <div class="relative flex justify-center">
            <span class="bg-violet-50 px-3 text-xs font-medium text-violet-500">After trade closes</span>
          </div>
        </div>

        <%!-- ── Zone 1: Trade Outcome ── --%>
        <div class="space-y-3">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <span class="block text-sm font-medium text-gray-700 mb-1">Rank</span>
              <div class="flex flex-wrap gap-1.5">
                <label class="cursor-pointer">
                  <input type="radio" name="rank" value="" checked={(Map.get(metadata, :rank) || Map.get(metadata, "rank")) in [nil, ""]} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">None</span>
                </label>
                <%= for rank_val <- v3_rank_options() do %>
                  <label class="cursor-pointer">
                    <input type="radio" name="rank" value={rank_val} checked={Map.get(metadata, :rank) == rank_val || Map.get(metadata, "rank") == rank_val} class="sr-only peer" />
                    <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{rank_val}</span>
                  </label>
                <% end %>
              </div>
            </div>
            <div>
              <span class="block text-sm font-medium text-gray-700 mb-1">Close Trigger</span>
              <div class="flex flex-wrap gap-1.5">
                <label class="cursor-pointer">
                  <input type="radio" name="close_trigger" value="" checked={(Map.get(metadata, :close_trigger) || Map.get(metadata, "close_trigger")) in [nil, ""]} class="sr-only peer" />
                  <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-500 peer-checked:bg-gray-500 peer-checked:text-white peer-checked:border-gray-500 transition">None</span>
                </label>
                <%= for opt <- close_trigger_options() do %>
                  <label class="cursor-pointer">
                    <input type="radio" name="close_trigger" value={opt} checked={Map.get(metadata, :close_trigger) == opt || Map.get(metadata, "close_trigger") == opt} class="sr-only peer" />
                    <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{opt}</span>
                  </label>
                <% end %>
              </div>
            </div>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div>
              <label for={"entry_timeslot_v3_#{@idx}"} class="block text-xs font-medium text-gray-500 mb-1">Entry Timeslot <span class="text-xs text-gray-400">(auto)</span></label>
              <input type="text" id={"entry_timeslot_v3_#{@idx}"}
                value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot") || Journalex.Notion.compute_entry_timeslot(@item)}
                placeholder="Auto" disabled
                class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed" />
            </div>
            <div>
              <label for={"close_timeslot_v3_#{@idx}"} class="block text-xs font-medium text-gray-500 mb-1">Close Timeslot <span class="text-xs text-gray-400">(auto)</span></label>
              <input type="text" id={"close_timeslot_v3_#{@idx}"}
                value={Map.get(metadata, :close_timeslot) || Map.get(metadata, "close_timeslot") || Journalex.Notion.compute_close_timeslot(@item)}
                placeholder="Auto" disabled
                class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed" />
            </div>
            <div>
              <label for={"sector_#{@idx}"} class="block text-xs font-medium text-gray-500 mb-1">Sector <span class="text-xs text-gray-400">(rollup)</span></label>
              <input type="text" id={"sector_#{@idx}"} value={Map.get(metadata, :sector) || Map.get(metadata, "sector")} placeholder="Via TickerLink" disabled class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed" />
            </div>
            <div>
              <label for={"cap_size_#{@idx}"} class="block text-xs font-medium text-gray-500 mb-1">Cap Size <span class="text-xs text-gray-400">(rollup)</span></label>
              <input type="text" id={"cap_size_#{@idx}"} value={Map.get(metadata, :cap_size) || Map.get(metadata, "cap_size")} placeholder="Via TickerLink" disabled class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed" />
            </div>
          </div>
        </div>

        <%!-- ── Zone 2: Risk & R:R ── --%>
        <div class="rounded-lg border border-violet-200 bg-violet-50 p-3 space-y-3">
          <p class="text-xs font-semibold uppercase tracking-wide text-violet-500">Risk &amp; R:R</p>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%!-- Initial R:R --%>
            <div id={"rr_initial_v3_#{@idx}"} phx-hook="RangeNumberSync">
              <label class="block text-xs text-gray-600 mb-1">Initial R:R</label>
              <div class="flex items-center gap-2">
                <input type="range" min="0" max="20" step="0.01"
                  value={format_decimal(Map.get(metadata, :initial_risk_reward_ratio) || Map.get(metadata, "initial_risk_reward_ratio"))}
                  class="flex-1 accent-violet-600 cursor-pointer" />
                <input type="number" name="initial_risk_reward_ratio" min="0" step="0.01"
                  value={format_decimal(Map.get(metadata, :initial_risk_reward_ratio) || Map.get(metadata, "initial_risk_reward_ratio"))}
                  class="w-20 px-2 py-1 text-sm border border-gray-300 rounded-md text-right focus:ring-violet-500 focus:border-violet-500" />
              </div>
            </div>
            <%!-- Better R:R? + Best R:R (compound) --%>
            <% best_rr_raw_v3 = Map.get(metadata, :best_risk_reward_ratio) || Map.get(metadata, "best_risk_reward_ratio") %>
            <% better_rr_checked = Map.get(metadata, :better_risk_reward_ratio?) || Map.get(metadata, "better_risk_reward_ratio?") || false %>
            <% best_rr_visible = better_rr_checked || best_rr_enabled?(best_rr_raw_v3) %>
            <div>
              <div class="flex items-center gap-2 mb-1.5">
                <label class="block text-xs text-gray-600">Better R:R?</label>
                <label class="cursor-pointer" title="Check when a better R:R was achievable; fill Best R:R below">
                  <input type="checkbox" name="better_risk_reward_ratio" value="true" checked={best_rr_visible} class="sr-only peer"
                    onchange={"document.getElementById('rr_best_v3_#{@idx}').classList.toggle('hidden', !this.checked)"} />
                  <span class="inline-block border rounded-full px-2.5 py-0.5 text-xs transition border-gray-300 text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600">Better R:R</span>
                </label>
              </div>
              <div id={"rr_best_v3_#{@idx}"} phx-hook="RangeNumberSync" class={if best_rr_visible, do: "", else: "hidden"}>
                <label class="block text-xs text-gray-500 mb-1 pl-1">Best R:R achieved</label>
                <div class="flex items-center gap-2">
                  <input type="range" min="0" max="20" step="0.01" value={format_decimal(best_rr_raw_v3, "0")} class="flex-1 accent-violet-600 cursor-pointer" />
                  <input type="number" name="best_risk_reward_ratio" min="0" step="0.01" value={format_decimal(best_rr_raw_v3, "0")} class="w-20 px-2 py-1 text-sm border border-gray-300 rounded-md text-right focus:ring-violet-500 focus:border-violet-500" />
                </div>
              </div>
            </div>
          </div>
          <%!-- Stop Loss quality --%>
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-xs text-gray-500">Stop Loss:</span>
            <label class="cursor-pointer">
              <input type="checkbox" name="too_tight_stop_loss" value="true" checked={Map.get(metadata, :too_tight_stop_loss?) || Map.get(metadata, "too_tight_stop_loss?")} class="sr-only peer" />
              <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">Too Tight</span>
            </label>
            <label class="cursor-pointer">
              <input type="checkbox" name="too_loose_stop_loss" value="true" checked={Map.get(metadata, :too_loose_stop_loss?) || Map.get(metadata, "too_loose_stop_loss?")} class="sr-only peer" />
              <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">Too Loose</span>
            </label>
          </div>
          <%!-- Size in R + R Value --%>
          <% r_size_v3 = @r_size || Journalex.Settings.get_r_size() %>
          <% size_in_r_val = compute_size_in_r_value(@item, metadata, r_size_v3) %>
          <% size_in_r_auto? = is_auto_size_in_r?(@item, metadata) %>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs text-gray-600 mb-1">Size in R</label>
              <input type="number" name="size_in_r" min="0" step="0.01"
                value={format_decimal(size_in_r_val, "")}
                placeholder={if size_in_r_auto?, do: "", else: "Enter size in R..."}
                class={[
                  "w-full px-3 py-1 text-sm border rounded-md text-left focus:ring-violet-500 focus:border-violet-500",
                  if(size_in_r_auto?, do: "border-violet-300 bg-violet-50 text-violet-800", else: "border-gray-300")
                ]} />
              <div :if={size_in_r_auto?} class="mt-1 flex items-center gap-1.5 rounded-md bg-violet-100 border border-violet-200 px-2 py-1">
                <span class="text-violet-500 text-xs">&#9889;</span>
                <span class="text-xs text-violet-700 font-medium">Auto-filled:</span>
                <span class="text-xs text-violet-600 font-mono">{auto_size_hint(@item, r_size_v3, size_in_r_val)}</span>
              </div>
            </div>
            <div>
              <label class="block text-xs text-gray-500 mb-1">R Value ($) <span class="text-xs text-gray-400">(from config)</span></label>
              <%!-- Hidden input submits r_value; visible input is display-only (disabled does not submit) --%>
              <input type="hidden" name="r_value" value={format_decimal(Map.get(metadata, :r_value) || Map.get(metadata, "r_value") || r_size_v3, "")} />
              <input type="number"
                value={format_decimal(Map.get(metadata, :r_value) || Map.get(metadata, "r_value") || r_size_v3, "")}
                disabled
                class="w-full px-3 py-1 text-sm border border-gray-200 rounded-md bg-gray-100 text-gray-500 cursor-not-allowed" />
            </div>
          </div>
          <%!-- Auto-calculate size_in_r when bound to a winning trade --%>
          <div class="mt-2 flex flex-wrap items-center gap-2">
            <label class="cursor-pointer">
              <input type="checkbox" name="auto_calculate_from_winning_trade" value="true"
                checked={Map.get(metadata, :auto_calculate_from_winning_trade?) || Map.get(metadata, "auto_calculate_from_winning_trade?")}
                class="sr-only peer" />
              <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-amber-500 peer-checked:text-white peer-checked:border-amber-500 transition">
                Auto-calc from winning trade
              </span>
            </label>
            <span class="text-xs text-gray-400 italic">on bind: |P/L| ÷ (r_size × initial R:R)</span>
            <% auto_calc_checked? = Map.get(metadata, :auto_calculate_from_winning_trade?) || Map.get(metadata, "auto_calculate_from_winning_trade?") %>
            <% v3_size_nil? = is_nil(Map.get(metadata, :size_in_r)) && is_nil(Map.get(metadata, "size_in_r")) %>
            <button
              :if={@on_recalculate_size_event && auto_calc_checked? && v3_size_nil?}
              type="button"
              phx-click={@on_recalculate_size_event}
              phx-value-index={@idx}
              class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium text-amber-800 bg-amber-100 border border-amber-300 rounded-full hover:bg-amber-200 transition"
              title="Auto-calculate is enabled but Size in R is empty — compute now"
            >
              &#9889; Compute now
            </button>
          </div>
        </div>

        <%!-- Close Time Comment + Extra Setup Comment (factual, before analysis flags) --%>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Close Time Comment</label>
          <div class="flex flex-wrap gap-1.5">
            <%= for option <- merge_current_multi_select_options(v3_close_time_comment_options(), metadata, :close_time_comment) do %>
              <label class="cursor-pointer">
                <input type="checkbox" name="close_time_comment[]" value={option} checked={option in parse_multi_select(metadata, :close_time_comment)} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{option}</span>
              </label>
            <% end %>
          </div>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Extra Setup Comment</label>
          <div class="flex flex-wrap gap-1.5">
            <%= for option <- merge_current_multi_select_options(v3_extra_setup_comment_options(), metadata, :extra_setup_comment) do %>
              <label class="cursor-pointer">
                <input type="checkbox" name="extra_setup_comment[]" value={option} checked={option in parse_multi_select(metadata, :extra_setup_comment)} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{option}</span>
              </label>
            <% end %>
          </div>
        </div>

        <%!-- ── Zone 3: Execution & Sizing ── --%>
        <div class="rounded-lg border border-violet-100 p-3 space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-violet-400">Execution &amp; Sizing</p>
          <%= for {group_label, flags} <- Enum.filter(v3_flag_groups(), fn {n, _} -> n in ["Self Assessment", "Sizing Intent", "Deviations"] end) do %>
            <div class="rounded border border-violet-100 bg-white px-3 py-2">
              <span class="block text-xs font-semibold uppercase tracking-wide text-violet-400 mb-1.5">{group_label}</span>
              <div class="flex flex-wrap gap-1.5">
                <%= for {flag_name, label} <- flags do %>
                  <label class="cursor-pointer">
                    <input type="checkbox" name={flag_name} value="true" checked={Map.get(metadata, String.to_atom(flag_name <> "?")) || Map.get(metadata, flag_name <> "?")} class="sr-only peer" />
                    <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{label}</span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- ── Zone 4: Context & Psychology ── --%>
        <div class="rounded-lg border border-violet-100 p-3 space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-violet-400">Context &amp; Psychology</p>
          <%= for {group_label, flags} <- Enum.filter(v3_flag_groups(), fn {n, _} -> n in ["Trade Context", "Psychology", "Follow Up"] end) do %>
            <div class="rounded border border-violet-100 bg-white px-3 py-2">
              <span class="block text-xs font-semibold uppercase tracking-wide text-violet-400 mb-1.5">{group_label}</span>
              <div class="flex flex-wrap gap-1.5">
                <%= for {flag_name, label} <- flags do %>
                  <label class="cursor-pointer">
                    <input type="checkbox" name={flag_name} value="true" checked={Map.get(metadata, String.to_atom(flag_name <> "?")) || Map.get(metadata, flag_name <> "?")} class="sr-only peer" />
                    <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{label}</span>
                  </label>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- ── Zone 5: Review & Notes ── --%>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Good Things</label>
          <div class="flex flex-wrap gap-1.5">
            <%= for option <- merge_current_multi_select_options(v3_good_things_options(), metadata, :good_things) do %>
              <label class="cursor-pointer">
                <input type="checkbox" name="good_things[]" value={option} checked={option in parse_multi_select(metadata, :good_things)} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{option}</span>
              </label>
            <% end %>
          </div>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Regular Lessons</label>
          <div class="flex flex-wrap gap-1.5">
            <%= for option <- merge_current_multi_select_options(v3_regular_lessons_options(), metadata, :regular_lessons) do %>
              <label class="cursor-pointer">
                <input type="checkbox" name="regular_lessons[]" value={option} checked={option in parse_multi_select(metadata, :regular_lessons)} class="sr-only peer" />
                <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">{option}</span>
              </label>
            <% end %>
          </div>
        </div>
        <%!-- Done / Lost Data (rarely used, at bottom) --%>
        <div class="flex flex-wrap gap-1.5 pt-1">
          <label class="cursor-pointer">
            <input type="checkbox" name="done" value="true" checked={Map.get(metadata, :done?) || Map.get(metadata, "done?")} class="sr-only peer" />
            <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">Done</span>
          </label>
          <label class="cursor-pointer">
            <input type="checkbox" name="lost_data" value="true" checked={Map.get(metadata, :lost_data?) || Map.get(metadata, "lost_data?")} class="sr-only peer" />
            <span class="inline-block border border-gray-300 rounded-full px-2.5 py-0.5 text-xs text-gray-600 peer-checked:bg-violet-600 peer-checked:text-white peer-checked:border-violet-600 transition">Lost Data</span>
          </label>
        </div>
        <%!-- Action buttons (Notion metadata) --%>
        <div class="flex justify-end space-x-2 pt-2 border-t border-violet-200">
          <button
            :if={not is_nil(@on_reset_event)}
            type="button"
            phx-click={@on_reset_event}
            phx-value-index={@idx}
            class="inline-flex items-center px-4 py-2 bg-white text-gray-700 text-sm font-medium rounded border border-gray-300 hover:bg-gray-50 transition"
            data-confirm="Clear all metadata for this trade?"
          >
            Reset
          </button>
          <button type="submit" class="inline-flex items-center px-4 py-2 bg-violet-600 text-white text-sm font-medium rounded hover:bg-violet-700 transition">
            {@save_label}
          </button>
        </div>
      </form>

      <%!-- ── APP JOURNAL section ── --%>
      <div class="mt-4 pt-4 border-t border-violet-200">
        <p class="text-xs font-semibold uppercase tracking-wide text-violet-400 mb-3">App Journal</p>

        <%!-- Progression Chain --%>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Progression Chain</label>
          <% chain = Map.get(@journal_data, "progression_chain") || Map.get(@journal_data, :progression_chain) || [] %>

          <%!-- Chain chip display --%>
          <div class="flex flex-wrap items-center gap-1 min-h-8 mb-3 p-2 bg-white rounded border border-violet-200">
            <%= if chain == [] do %>
              <span class="text-xs text-gray-400 italic">No chain yet — add ENTRY to start</span>
            <% else %>
              <%= for {token, i} <- Enum.with_index(chain) do %>
                <%= if i > 0 do %>
                  <span class="text-gray-400 text-xs">→</span>
                <% end %>
                <span class={[
                  "inline-block rounded-full px-2.5 py-0.5 text-xs font-medium",
                  v3_chain_token_class(token)
                ]}>{token}</span>
              <% end %>
            <% end %>
          </div>

          <%!-- Add-token buttons --%>
          <div class="space-y-1.5">
            <%!-- ENTRY --%>
            <div class="flex flex-wrap gap-1.5">
              <button type="button" phx-click="v3_chain_add_token" phx-value-token="ENTRY" phx-value-index={@idx}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-gray-700 text-white hover:bg-gray-900 transition">
                ENTRY
              </button>
            </div>
            <%!-- Band tokens --%>
            <div class="flex flex-wrap gap-1.5">
              <%= for token <- ["W25", "W50", "W75"] do %>
                <button type="button" phx-click="v3_chain_add_token" phx-value-token={token} phx-value-index={@idx}
                  class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-green-100 text-green-800 border border-green-200 hover:bg-green-200 transition">
                  {token}
                </button>
              <% end %>
              <span class="text-gray-300 self-center">|</span>
              <%= for token <- ["L25", "L50", "L75"] do %>
                <button type="button" phx-click="v3_chain_add_token" phx-value-token={token} phx-value-index={@idx}
                  class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-red-100 text-red-800 border border-red-200 hover:bg-red-200 transition">
                  {token}
                </button>
              <% end %>
            </div>
            <%!-- Terminal tokens --%>
            <div class="flex flex-wrap gap-1.5">
              <button type="button" phx-click="v3_chain_add_token" phx-value-token="TARGET" phx-value-index={@idx}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-emerald-600 text-white hover:bg-emerald-700 transition">
                TARGET
              </button>
              <button type="button" phx-click="v3_chain_add_token" phx-value-token="STOPLOSS" phx-value-index={@idx}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-rose-600 text-white hover:bg-rose-700 transition">
                STOPLOSS
              </button>
              <button type="button" phx-click="v3_chain_add_token" phx-value-token="MANUAL_WIN" phx-value-index={@idx}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-teal-600 text-white hover:bg-teal-700 transition">
                MANUAL_WIN
              </button>
              <button type="button" phx-click="v3_chain_add_token" phx-value-token="MANUAL_LOSE" phx-value-index={@idx}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-orange-600 text-white hover:bg-orange-700 transition">
                MANUAL_LOSE
              </button>
              <button type="button" phx-click="v3_chain_add_token" phx-value-token="BREAKEVEN" phx-value-index={@idx}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-slate-500 text-white hover:bg-slate-600 transition">
                BREAKEVEN
              </button>
            </div>
            <%!-- Undo / Clear --%>
            <div class="flex gap-2 pt-1">
              <button type="button" phx-click="v3_chain_undo" phx-value-index={@idx}
                :if={chain != []}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-white border border-gray-300 text-gray-600 hover:bg-gray-50 transition">
                Undo Last
              </button>
              <button type="button" phx-click="v3_chain_clear" phx-value-index={@idx}
                :if={chain != []}
                class="inline-flex items-center px-3 py-1 rounded text-xs font-medium bg-white border border-red-200 text-red-600 hover:bg-red-50 transition"
                data-confirm="Clear the progression chain for this trade?">
                Clear Chain
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ─── V3 helper functions ─────────────────────────────────────────────────

  defp v3_rank_options, do: ["Not Setup", "Bad Setup", "C Trade", "B Trade", "A Trade"]

  defp v3_setup_options do
    [
      "Bouncy Ball - Big Seller/Buyer",
      "Breakout - Day High/Low",
      "Reversal - Capitulation",
      "Reversal - Day High/Low",
      "Reversal - Pullback Reversal",
      "Testing Setup",
      "Not Setup"
    ]
  end

  # App-defined defaults. If Notion contains additional synced values not listed here,
  # the form preserves and renders them via merge_current_multi_select_options/3.
  defp v3_close_time_comment_options do
    [
      "Consider stop loss",
      "Consider lock profit",
      "Early close",
      "Correct early close",
      "Will lose more if not close",
      "Will win more if not close",
      "Will hit take profit if not close",
      "Will hit stop loss if not close"
    ]
  end

  defp v3_extra_setup_comment_options do
    [
      "Straight losing",
      "Zero risk play",
      "Liquidity grab",
      "Just hit target then reverse",
      "Just hit stoploss then reverse",
      "Reverse right before hitting target",
      "Reverse right before hitting stop loss",
      "Reverse right before hitting stoploss"
    ]
  end

  defp v3_good_things_options do
    [
      "Nothing Good",
      "Good spotting setup",
      "Good following plan",
      "Good try",
      "Good execution",
      "Good adjusting stop loss",
      "Good cut",
      "Good small size",
      "Good big size",
      "Good add size",
      "Good second try",
      "Good target",
      "Good learning from Alvin",
      "Good learning from Jason"
    ]
  end

  defp v3_patterns_options do
    [
      {"Chart Structure", [
        "Key level - Intraday",
        "Key level - Multiday",
        "Consolidation range",
        "Volume level",
        "Double top/bottom"
      ]},
      {"Candle Patterns", [
        "Three inside down",
        "Gravestone doji",
        "Engulfing candle",
        "Sharp top round top"
      ]},
      {"Momentum", [
        "Tight Bouncy Ball",
        "Overbought/Oversold",
        "Tight selling/buying",
        "Capitulation",
        "Spike Volume"
      ]},
      {"Other", [
        "Lead Lag",
        "Sudden Market Shift",
        "VWAP reversal",
        "1min 50ma Reversal",
        "2min 50ma Reversal",
        "N/A"
      ]}
    ]
  end

  defp v3_regular_lessons_options do
    [
      "Mental",
      "Discipline",
      "Patience",
      "Be Selective",
      "Risk Management",
      "Sizing"
    ]
  end

  # V3 flag groups — 8 groups, 39 total flags (Done/Lost Data are rendered separately)
  defp v3_flag_groups do
    [
      {"Trade Nature", [
        {"follow_up_trial", "Follow Up Trial"},
        {"scalp", "Scalp"}
      ]},
      {"Setup Context", [
        {"align_global_trend", "Align Global Trend"},
        {"align_sector_trend", "Align Sector Trend"},
        {"align_ticker_big_picture_trend", "Align Ticker Big Picture Trend"},
        {"align_ticker_intraday_trend", "Align Ticker Intraday Trend"},
        {"hot_sector", "Hot Sector"},
        {"news", "News"},
        {"earning_report", "Earning Report"},
        {"choppy_chart", "Choppy Chart"},
        {"mid_range", "Mid Range"},
        {"random_intraday_trend", "Random Intraday Trend"}
      ]},
      {"Self Assessment", [
        {"following_rule", "Following Rule"},
        {"normal_emotion", "Normal Emotion"},
        {"reasonable_entry_story", "Reasonable Entry Story"},
        {"reasonable_exit_story", "Reasonable Exit Story"},
        {"size_matching_story", "Size Matching Story"}
      ]},
      {"Sizing Intent", [
        {"large_size_in_purpose", "Large Size (on purpose)"},
        {"small_size_in_purpose", "Small Size (on purpose)"},
        {"averaging_up", "Averaging Up"},
        {"averaging_down", "Averaging Down"}
      ]},
      {"Deviations", [
        {"slippage_entry", "Slippage Entry"},
        {"operation_mistake", "Operation Mistake"},
        {"adjusted_stoploss", "Adjusted Stoploss"},
        {"adjusted_target", "Adjusted Target"}
      ]},
      {"Risk / R:R", [
        {"better_risk_reward_ratio", "Better R:R"},
        {"too_tight_stop_loss", "Too Tight Stop Loss"},
        {"too_loose_stop_loss", "Too Loose Stop Loss"}
      ]},
      {"Psychology", [
        {"revenge_trade", "Revenge Trade"},
        {"fomo", "FOMO"},
        {"lack_confidence", "Lack Confidence"},
        {"close_trade_remorse", "Close Trade Remorse"},
        {"decision_affected_by_other_trade", "Decision Affected by Other Trade"}
      ]},
      {"Trade Context", [
        {"overnight", "Overnight"},
        {"overnight_in_purpose", "Overnight in Purpose"},
        {"fully_wrong_direction", "Fully Wrong Direction"}
      ]},
      {"Follow Up", [
        {"following_trade", "Following Trade"},
        {"good_lesson", "Good Lesson"},
        {"should_record_obsidian", "Should Record Obsidian"}
      ]}
    ]
  end

  # CSS classes for progression chain tokens
  defp v3_chain_token_class("ENTRY"),       do: "bg-gray-700 text-white"
  defp v3_chain_token_class("W" <> _),      do: "bg-green-100 text-green-800 border border-green-200"
  defp v3_chain_token_class("L" <> _),      do: "bg-red-100 text-red-800 border border-red-200"
  defp v3_chain_token_class("TARGET"),      do: "bg-emerald-600 text-white"
  defp v3_chain_token_class("STOPLOSS"),    do: "bg-rose-600 text-white"
  defp v3_chain_token_class("MANUAL_WIN"),  do: "bg-teal-600 text-white"
  defp v3_chain_token_class("MANUAL_LOSE"), do: "bg-orange-600 text-white"
  defp v3_chain_token_class("BREAKEVEN"),   do: "bg-slate-500 text-white"
  defp v3_chain_token_class(_),             do: "bg-gray-200 text-gray-700"

  # Compute SizeInR for V3 (mirrors V2 compute_size_value but uses :size_in_r key)
  defp compute_size_in_r_value(item, metadata, r_size) do
    existing = Map.get(metadata, :size_in_r) || Map.get(metadata, "size_in_r")
    if not is_nil(existing) do
      existing
    else
      result = Map.get(item, :result) || Map.get(item, "result")
      realized = Map.get(item, :realized_pl) || Map.get(item, "realized_pl")
      if result == "LOSE" and not is_nil(realized) and r_size > 0 do
        pl = to_pl_float(realized)
        computed = Float.round(abs(pl) / r_size, 2)
        if computed > 0, do: Decimal.from_float(computed), else: nil
      else
        nil
      end
    end
  end

  defp is_auto_size_in_r?(item, metadata) do
    is_nil(Map.get(metadata, :size_in_r)) and
      is_nil(Map.get(metadata, "size_in_r")) and
      (Map.get(item, :result) || Map.get(item, "result")) == "LOSE"
  end

  # Parse a comma-separated multi_select string into a list (generic, replaces parse_close_time_comments)
  defp parse_multi_select(metadata, field) when is_atom(field) do
    raw = Map.get(metadata, field) || Map.get(metadata, Atom.to_string(field)) || ""
    raw |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp merge_current_multi_select_options(options, metadata, field)
       when is_list(options) and is_atom(field) do
    current = parse_multi_select(metadata, field)
    options ++ Enum.reject(current, &(&1 in options))
  end
end

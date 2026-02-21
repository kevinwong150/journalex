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

  def v1(assigns) do
    ~H"""
    <div class="rounded-lg border border-indigo-200 bg-indigo-50 p-4 shadow-sm mb-3">
      <h4 class="text-sm font-semibold text-indigo-800 mb-3">Trade Metadata (V1)</h4>

      <form phx-submit={@on_save_event} phx-value-index={@idx} class="space-y-4">
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
              <%= for opt <- setup_options() do %>
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
              value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot")}
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
            Save Metadata
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

  def v2(assigns) do
    ~H"""
    <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 shadow-sm mb-3">
      <h4 class="text-sm font-semibold text-blue-800 mb-3">Trade Metadata (V2)</h4>

      <form phx-submit={@on_save_event} phx-value-index={@idx} class="space-y-4">
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
              <%= for opt <- setup_options() do %>
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

          <!-- Entry Timeslot (read-only, auto-calculated from action chain) -->
          <div>
            <label for={"entry_timeslot_#{@idx}"} class="block text-sm font-medium text-gray-500 mb-1">
              Entry Timeslot <span class="text-xs text-gray-400">(auto)</span>
            </label>
            <input
              type="text"
              id={"entry_timeslot_#{@idx}"}
              value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot")}
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
              value={Map.get(metadata, :close_timeslot) || Map.get(metadata, "close_timeslot")}
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
            Save Metadata
          </button>
        </div>
      </form>
    </div>
    """
  end

  # --- Option lists matching Notion select/multi_select fields ---

  defp v1_rank_options, do: ["BAD Trade", "C Trade", "B Trade", "A Trade"]
  defp v2_rank_options, do: ["Bad Setup", "Not Setup", "C Trade", "B Trade", "A Trade"]

  defp setup_options do
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

  defp close_trigger_options do
    [
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

  defp entry_timeslot_options do
    [
      "0930-1000", "1000-1030", "1030-1100", "1100-1130", "1130-1200",
      "1200-1230", "1230-1300", "1300-1330", "1330-1400", "1400-1430",
      "1430-1500", "1500-1530", "1530-1600", "1600-1630", "1630-1700"
    ]
  end

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
  defp option_id(str) when is_binary(str) do
    str |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
  end

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

  # V2 metadata analysis flags — grouped by theme
  defp v2_flag_groups do
    [
      {"Setup Context", [
        {"align_with_trend", "Align w/ Trend"},
        {"big_picture", "Big Picture"},
        {"hot_sector", "Hot Sector"},
        {"momentum", "Momentum"},
        {"news", "News"},
        {"earning_report", "Earning Report"}
      ]},
      {"Execution", [
        {"adjusted_risk_reward", "Adjusted R:R"},
        {"add_size", "Add Size"},
        {"follow_up_trial", "Follow Up Trial"},
        {"skipped_position", "Slipped Position"},
        {"operation_mistake", "Operation Mistake"}
      ]},
      {"Reflection", [
        {"normal_emotion", "Normal Emotion"},
        {"good_lesson", "Good Lesson"},
        {"better_risk_reward_ratio", "Better R:R"}
      ]},
      {"Discipline", [
        {"revenge_trade", "Revenge Trade"},
        {"fomo", "FOMO"},
        {"overnight", "Overnight"},
        {"overnight_in_purpose", "Overnight in Purpose"}
      ]}
    ]
  end
end

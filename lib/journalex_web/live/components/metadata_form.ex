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

  def v1(assigns) do
    ~H"""
    <div class="rounded-lg border border-indigo-200 bg-indigo-50 p-4 shadow-sm mb-3">
      <h4 class="text-sm font-semibold text-indigo-800 mb-3">Trade Metadata (V1)</h4>

      <form phx-submit={@on_save_event} phx-value-index={@idx} class="space-y-4">
        <% metadata = Map.get(@item, :metadata) || %{} %>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <!-- Done checkbox -->
          <div class="flex items-center space-x-2">
            <input
              type="checkbox"
              name="done"
              id={"done_#{@idx}"}
              value="true"
              checked={Map.get(metadata, :done?) || Map.get(metadata, "done?")}
              class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
            />
            <label for={"done_#{@idx}"} class="text-sm font-medium text-gray-700">
              Done
            </label>
          </div>

          <!-- Lost Data checkbox -->
          <div class="flex items-center space-x-2">
            <input
              type="checkbox"
              name="lost_data"
              id={"lost_data_#{@idx}"}
              value="true"
              checked={Map.get(metadata, :lost_data?) || Map.get(metadata, "lost_data?")}
              class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
            />
            <label for={"lost_data_#{@idx}"} class="text-sm font-medium text-gray-700">
              Lost Data
            </label>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <!-- Rank select -->
          <div>
            <label for={"rank_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Rank
            </label>
            <select
              name="rank"
              id={"rank_#{@idx}"}
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            >
              <option value="">Select rank...</option>
              <%= for rank_val <- ["Not Setup", "C Trade", "B Trade", "A Trade"] do %>
                <option value={rank_val} selected={Map.get(metadata, :rank) == rank_val || Map.get(metadata, "rank") == rank_val}>
                  {rank_val}
                </option>
              <% end %>
            </select>
          </div>

          <!-- Setup input -->
          <div>
            <label for={"setup_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Setup
            </label>
            <input
              type="text"
              name="setup"
              id={"setup_#{@idx}"}
              value={Map.get(metadata, :setup) || Map.get(metadata, "setup")}
              placeholder="e.g., Breakout - Day High/Low"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            />
          </div>

          <!-- Close Trigger input -->
          <div>
            <label for={"close_trigger_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Close Trigger
            </label>
            <input
              type="text"
              name="close_trigger"
              id={"close_trigger_#{@idx}"}
              value={Map.get(metadata, :close_trigger) || Map.get(metadata, "close_trigger")}
              placeholder="e.g., Automatically - Take Profit"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            />
          </div>

          <!-- Sector input -->
          <div>
            <label for={"sector_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Sector
            </label>
            <input
              type="text"
              name="sector"
              id={"sector_#{@idx}"}
              value={Map.get(metadata, :sector) || Map.get(metadata, "sector")}
              placeholder="e.g., Finance - Bank"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            />
          </div>

          <!-- Cap Size input -->
          <div>
            <label for={"cap_size_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Cap Size
            </label>
            <input
              type="text"
              name="cap_size"
              id={"cap_size_#{@idx}"}
              value={Map.get(metadata, :cap_size) || Map.get(metadata, "cap_size")}
              placeholder="e.g., > 100B"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            />
          </div>

          <!-- Entry Timeslot input -->
          <div>
            <label for={"entry_timeslot_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Entry Timeslot
            </label>
            <input
              type="text"
              name="entry_timeslot"
              id={"entry_timeslot_#{@idx}"}
              value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot")}
              placeholder="e.g., 1300-1330"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
            />
          </div>
        </div>

        <!-- Trade Characteristics -->
        <div>
          <h5 class="text-sm font-medium text-gray-700 mb-2">Trade Characteristics</h5>
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
            <%= for {flag_name, label} <- v1_flags() do %>
              <div class="flex items-center space-x-2">
                <input
                  type="checkbox"
                  name={flag_name}
                  id={"#{flag_name}_#{@idx}"}
                  value="true"
                  checked={Map.get(metadata, String.to_atom(flag_name)) || Map.get(metadata, flag_name)}
                  class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
                />
                <label for={"#{flag_name}_#{@idx}"} class="text-xs text-gray-600">
                  {label}
                </label>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Close Time Comment -->
        <div>
          <label for={"close_time_comment_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
            Close Time Comment
          </label>
          <textarea
            name="close_time_comment"
            id={"close_time_comment_#{@idx}"}
            rows="3"
            placeholder="Add notes about the trade close..."
            class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-indigo-500 focus:border-indigo-500"
          >{Map.get(metadata, :close_time_comment) || Map.get(metadata, "close_time_comment")}</textarea>
        </div>

        <!-- Action buttons -->
        <div class="flex justify-end space-x-2 pt-2 border-t border-indigo-200">
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

  def v2(assigns) do
    ~H"""
    <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 shadow-sm mb-3">
      <h4 class="text-sm font-semibold text-blue-800 mb-3">Trade Metadata (V2)</h4>

      <form phx-submit={@on_save_event} phx-value-index={@idx} class="space-y-4">
        <% metadata = Map.get(@item, :metadata) || %{} %>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <!-- Done checkbox -->
          <div class="flex items-center space-x-2">
            <input
              type="checkbox"
              name="done"
              id={"done_#{@idx}"}
              value="true"
              checked={Map.get(metadata, :done?) || Map.get(metadata, "done?")}
              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
            />
            <label for={"done_#{@idx}"} class="text-sm font-medium text-gray-700">
              Done
            </label>
          </div>

          <!-- Lost Data checkbox -->
          <div class="flex items-center space-x-2">
            <input
              type="checkbox"
              name="lost_data"
              id={"lost_data_#{@idx}"}
              value="true"
              checked={Map.get(metadata, :lost_data?) || Map.get(metadata, "lost_data?")}
              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
            />
            <label for={"lost_data_#{@idx}"} class="text-sm font-medium text-gray-700">
              Lost Data
            </label>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <!-- Rank select -->
          <div>
            <label for={"rank_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Rank
            </label>
            <select
              name="rank"
              id={"rank_#{@idx}"}
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            >
              <option value="">Select rank...</option>
              <%= for rank_val <- ["Not Setup", "C Trade", "B Trade", "A Trade"] do %>
                <option
                  value={rank_val}
                  selected={
                    Map.get(metadata, :rank) == rank_val || Map.get(metadata, "rank") == rank_val
                  }
                >
                  {rank_val}
                </option>
              <% end %>
            </select>
          </div>

          <!-- Setup input -->
          <div>
            <label for={"setup_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Setup
            </label>
            <input
              type="text"
              name="setup"
              id={"setup_#{@idx}"}
              value={Map.get(metadata, :setup) || Map.get(metadata, "setup")}
              placeholder="e.g., Breakout - Day High/Low"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            />
          </div>

          <!-- Close Trigger input -->
          <div>
            <label for={"close_trigger_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Close Trigger
            </label>
            <input
              type="text"
              name="close_trigger"
              id={"close_trigger_#{@idx}"}
              value={Map.get(metadata, :close_trigger) || Map.get(metadata, "close_trigger")}
              placeholder="e.g., Automatically - Take Profit"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            />
          </div>

          <!-- Sector input -->
          <div>
            <label for={"sector_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Sector
            </label>
            <input
              type="text"
              name="sector"
              id={"sector_#{@idx}"}
              value={Map.get(metadata, :sector) || Map.get(metadata, "sector")}
              placeholder="e.g., Technology"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            />
          </div>

          <!-- Cap Size input -->
          <div>
            <label for={"cap_size_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Cap Size
            </label>
            <input
              type="text"
              name="cap_size"
              id={"cap_size_#{@idx}"}
              value={Map.get(metadata, :cap_size) || Map.get(metadata, "cap_size")}
              placeholder="e.g., Large"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            />
          </div>

          <!-- Entry Timeslot input -->
          <div>
            <label for={"entry_timeslot_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
              Entry Timeslot
            </label>
            <input
              type="text"
              name="entry_timeslot"
              id={"entry_timeslot_#{@idx}"}
              value={Map.get(metadata, :entry_timeslot) || Map.get(metadata, "entry_timeslot")}
              placeholder="e.g., 1300-1330"
              class="w-full px-3 py-1 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
        </div>

        <!-- Trade Analysis Flags -->
        <div>
          <h5 class="text-sm font-medium text-gray-700 mb-2">Trade Analysis</h5>
          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
            <%= for {flag_name, label} <- v2_flags() do %>
              <div class="flex items-center space-x-2">
                <input
                  type="checkbox"
                  name={flag_name}
                  id={"#{flag_name}_#{@idx}"}
                  value="true"
                  checked={Map.get(metadata, String.to_atom(flag_name)) || Map.get(metadata, flag_name)}
                  class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                />
                <label for={"#{flag_name}_#{@idx}"} class="text-xs text-gray-600">
                  {label}
                </label>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Close Time Comment -->
        <div>
          <label for={"close_time_comment_#{@idx}"} class="block text-sm font-medium text-gray-700 mb-1">
            Close Time Comment
          </label>
          <textarea
            name="close_time_comment"
            id={"close_time_comment_#{@idx}"}
            rows="3"
            placeholder="Add notes about the trade close..."
            class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
          >{Map.get(metadata, :close_time_comment) || Map.get(metadata, "close_time_comment")}</textarea>
        </div>

        <!-- Action buttons -->
        <div class="flex justify-end space-x-2 pt-2 border-t border-blue-200">
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

  # V1 metadata characteristic flags
  defp v1_flags do
    [
      {"operation_mistake", "Operation Mistake"},
      {"follow_setup", "Follow Setup"},
      {"follow_stop_loss_management", "Follow Stop Loss Mgmt"},
      {"revenge_trade", "Revenge Trade"},
      {"fomo", "FOMO"},
      {"unnecessary_trade", "Unnecessary Trade"}
    ]
  end

  # V2 metadata analysis flags
  defp v2_flags do
    [
      {"revenge_trade", "Revenge Trade"},
      {"fomo", "FOMO"},
      {"add_size", "Add Size"},
      {"adjusted_risk_reward", "Adjusted R:R"},
      {"align_with_trend", "Align w/ Trend"},
      {"better_risk_reward_ratio", "Better R:R"},
      {"big_picture", "Big Picture"},
      {"earning_report", "Earning Report"},
      {"follow_up_trial", "Follow Up Trial"},
      {"good_lesson", "Good Lesson"},
      {"hot_sector", "Hot Sector"},
      {"momentum", "Momentum"},
      {"news", "News"},
      {"normal_emotion", "Normal Emotion"},
      {"operation_mistake", "Operation Mistake"},
      {"overnight", "Overnight"},
      {"overnight_in_purpose", "Overnight in Purpose"},
      {"skipped_position", "Skipped Position"}
    ]
  end
end

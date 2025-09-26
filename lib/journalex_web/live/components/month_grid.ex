defmodule JournalexWeb.MonthGrid do
  use JournalexWeb, :html

  @moduledoc """
  Function component to render a month calendar grid (like a date picker, not selectable).

  Expects months data in the same shape as produced by build_date_grid/3:
    [%{label: String.t(), weeks: [[cell]]}]

  Where each cell is a map with keys:
    - :date => %Date{} | nil
    - :in_range => boolean (whether within selected range)
    - :has => boolean (whether there is data for that day)

  New optional attributes:
    - :start_date => %Date{} | nil (start of a highlighted selection)
    - :end_date => %Date{} | nil (end of a highlighted selection)

  If both start_date and end_date are provided, days within the inclusive
  range are visually highlighted in the grid.
  """

  attr :months, :list, required: true
  attr :show_nav, :boolean, default: false
  attr :current_month, :any, default: nil
  attr :prev_event, :string, default: "prev_month"
  attr :next_event, :string, default: "next_month"
  attr :title, :string, default: "Dates"
  # New optional selection attrs
  attr :start_date, :any, default: nil
  attr :end_date, :any, default: nil

  def month_grid(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-sm font-semibold text-gray-700">{@title}</h2>

        <%= if @show_nav and match?(%Date{}, @current_month) do %>
          <div class="flex items-center gap-2">
            <button
              phx-click={@prev_event}
              class="px-2 py-1 text-sm border rounded-md hover:bg-gray-50"
            >
              Prev
            </button>
            <div class="text-sm text-gray-700">
              {month_label(@current_month)}
            </div>

            <button
              phx-click={@next_event}
              class="px-2 py-1 text-sm border rounded-md hover:bg-gray-50"
            >
              Next
            </button>
          </div>
        <% end %>
      </div>

      <div class="space-y-6">
        <%= for month <- @months do %>
          <div>
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-sm font-medium text-gray-900">{month.label}</h3>
            </div>

            <div class="grid grid-cols-7 gap-1 text-xs text-gray-500 mb-1">
              <div class="text-center">Sun</div>

              <div class="text-center">Mon</div>

              <div class="text-center">Tue</div>

              <div class="text-center">Wed</div>

              <div class="text-center">Thu</div>

              <div class="text-center">Fri</div>

              <div class="text-center">Sat</div>
            </div>

            <div class="grid grid-cols-7 gap-1">
              <%= for cell <- List.flatten(month.weeks) do %>
                <% date = cell[:date] %>
                <% selected? = in_range?(date, @start_date, @end_date, false) %>
                <div class={
                       [
                         "h-16 border rounded-md p-1 flex flex-col justify-between",
                         date == nil && "bg-gray-50",
                         selected? && "bg-indigo-50 ring-1 ring-indigo-300"
                       ]
                     }>
                  <div class={
                         [
                           "text-[10px] text-right",
                           selected? && "text-indigo-800",
                           (not selected?) && "text-gray-400"
                         ]
                       }>
                    {if date, do: day_of_month(date), else: ""}
                  </div>

                  <div class="text-center">
                    <%= if date do %>
                      <%= if weekend?(date) do %>
                        <span class="inline-block text-lg text-transparent">-</span>
                      <% else %>
                        <span class={[
                          "inline-block text-lg font-bold",
                          cell[:has] && "text-green-600",
                          (not cell[:has]) && "text-red-600"
                        ]}>
                          {if cell[:has], do: "✓", else: "✗"}
                        </span>
                      <% end %>
                    <% else %>
                      <span class="inline-block text-lg text-transparent">-</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp month_label(%Date{year: y, month: m}) do
    month_names =
      ~w(January February March April May June July August September October November December)

    name = Enum.at(month_names, m - 1)
    "#{name} #{y}"
  end

  defp day_of_month(%Date{day: d}), do: d

  # Determine if the given date should be considered selected/in-range.
  # Only highlight when both start_date and end_date are provided.
  defp in_range?(nil, _s, _e, _fallback), do: false
  defp in_range?(%Date{} = _date, nil, _e, _fallback), do: false
  defp in_range?(%Date{} = _date, _s, nil, _fallback), do: false
  defp in_range?(%Date{} = date, %Date{} = s, %Date{} = e, _fallback) do
    {start_d, end_d} = if Date.compare(s, e) == :gt, do: {e, s}, else: {s, e}
    Date.compare(date, start_d) in [:eq, :gt] and Date.compare(date, end_d) in [:eq, :lt]
  end

  defp weekend?(%Date{} = date) do
    case Date.day_of_week(date) do
      6 -> true
      7 -> true
      _ -> false
    end
  end
end

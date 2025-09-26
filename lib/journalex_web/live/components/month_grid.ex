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
  """

  attr :months, :list, required: true
  attr :show_nav, :boolean, default: false
  attr :current_month, :any, default: nil
  attr :prev_event, :string, default: "prev_month"
  attr :next_event, :string, default: "next_month"
  attr :title, :string, default: "Dates"

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
                <div class={"h-16 border rounded-md p-1 flex flex-col justify-between #{if cell[:date] == nil, do: "bg-gray-50"}"}>
                  <div class={"text-[10px] text-right #{if cell[:in_range], do: "text-gray-700", else: "text-gray-400"}"}>
                    {if cell[:date], do: day_of_month(cell[:date]), else: ""}
                  </div>
                  
                  <div class="text-center">
                    <%= if cell[:date] && cell[:in_range] do %>
                      <span class={"inline-block text-lg font-bold #{if cell[:has], do: "text-green-600", else: "text-red-600"}"}>
                        {if cell[:has], do: "✓", else: "✗"}
                      </span>
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
end

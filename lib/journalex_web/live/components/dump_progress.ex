defmodule JournalexWeb.DumpProgress do
  @moduledoc """
  Generic progress UI for long-running operations (insert/update).
  """

  use JournalexWeb, :html

  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :processed, :integer, required: true
  attr :total, :integer, required: true
  attr :in_progress?, :boolean, required: true
  attr :elapsed_ms, :integer, default: 0
  attr :current_text, :string, default: nil
  attr :metrics, :map, default: %{}
  attr :labels, :map, default: %{}

  def progress(assigns) do
    ~H"""
    <div :if={@total > 0} class="w-full space-y-1">
      <% percent = if @total > 0, do: Float.round(@processed * 100.0 / @total, 1), else: 0.0 %>
      <div class="flex items-center justify-between text-xs text-gray-600">
        <span>
          {@title || "Progress"}: {@processed}/{@total} ({percent}%) {if @in_progress?, do: "- in progress", else: "- completed"} · Time: {format_duration(@elapsed_ms)}
        </span>
        <span :if={@current_text} class="font-medium text-gray-700">
          Currently: {@current_text}
        </span>
      </div>

      <div class="w-full bg-gray-200 rounded h-2 overflow-hidden">
        <div class="bg-green-500 h-2" style={"width: #{percent}%"}></div>
      </div>

      <div class="text-xs text-gray-700">
        <div class="flex items-center gap-2 flex-wrap">
          <%= for {key, value} <- @metrics do %>
            <% label = Map.get(@labels, key, key |> to_string() |> String.capitalize()) %>
            <% {bg, text} = pill_colors(key) %>
            <span class={["inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium", bg, text]}>
              {label}: {value}
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp pill_colors(:created), do: {"bg-green-100", "text-green-700"}
  defp pill_colors(:skipped), do: {"bg-gray-100", "text-gray-700"}
  defp pill_colors(:retrying), do: {"bg-yellow-100", "text-yellow-700"}
  defp pill_colors(:errors), do: {"bg-red-100", "text-red-700"}
  defp pill_colors(:remaining), do: {"bg-blue-100", "text-blue-700"}
  defp pill_colors(_), do: {"bg-gray-100", "text-gray-700"}

  defp format_duration(ms) when is_integer(ms) and ms >= 0 do
    total_ms = ms
  hours = div(total_ms, 3_600_000)
  rem_after_h = rem(total_ms, 3_600_000)
    minutes = div(rem_after_h, 60_000)
    rem_after_m = rem(rem_after_h, 60_000)
    seconds = div(rem_after_m, 1_000)
    millis = rem(rem_after_m, 1_000)

    if hours > 0 do
      :io_lib.format("~B:~2..0B:~2..0B.~3..0B", [hours, minutes, seconds, millis])
      |> IO.iodata_to_binary()
    else
      :io_lib.format("~B:~2..0B.~3..0B", [minutes, seconds, millis]) |> IO.iodata_to_binary()
    end
  end

  defp format_duration(_), do: "0:00.000"
end

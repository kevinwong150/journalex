defmodule JournalexWeb.KpiCard do
  use JournalexWeb, :html

  import JournalexWeb.InfoTooltip

  @moduledoc """
  Renders a KPI metric card with an optional delta indicator.
  """

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tooltip, :string, default: nil
  attr :delta, :string, default: nil
  attr :delta_direction, :atom, default: nil, values: [:up, :down, nil]
  attr :class, :string, default: ""

  def kpi_card(assigns) do
    ~H"""
    <div class={"rounded-lg border border-zinc-200 bg-white p-4 shadow-sm #{@class}"}>
      <p class="flex items-center text-xs font-semibold uppercase tracking-wider text-zinc-400">
        <%= @label %>
        <%= if @tooltip do %><.info_tooltip text={@tooltip} /><% end %>
      </p>
      <p class="mt-1 text-2xl font-bold text-zinc-900"><%= @value %></p>
      <%= if @delta do %>
        <p class={"mt-1 text-xs font-medium #{delta_color(@delta_direction)}"}>
          <%= delta_arrow(@delta_direction) %><%= @delta %>
        </p>
      <% end %>
    </div>
    """
  end

  defp delta_color(:up), do: "text-emerald-600"
  defp delta_color(:down), do: "text-rose-600"
  defp delta_color(nil), do: "text-zinc-400"

  defp delta_arrow(:up), do: "▲ "
  defp delta_arrow(:down), do: "▼ "
  defp delta_arrow(nil), do: ""
end

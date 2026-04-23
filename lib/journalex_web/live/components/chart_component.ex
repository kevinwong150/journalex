defmodule JournalexWeb.ChartComponent do
  use JournalexWeb, :html

  @moduledoc """
  Renders an ECharts chart wired to the `Hooks.Chart` LiveView hook.

  The `option` map is built server-side in Elixir and JSON-encoded into
  `data-option`. Never build chart options in JavaScript.

  Usage:
      <.chart id="equity-curve" option={@equity_option} class="w-full h-64" />
  """

  attr :id, :string, required: true
  attr :option, :map, required: true
  attr :class, :string, default: "w-full h-64"

  def chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Chart"
      phx-update="ignore"
      data-option={Jason.encode!(@option)}
      class={@class}
    />
    """
  end
end

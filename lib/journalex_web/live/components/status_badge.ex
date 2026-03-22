defmodule JournalexWeb.StatusBadge do
  @moduledoc """
  Shared status badge component for displaying labeled pill-style badges.
  """

  use JournalexWeb, :html

  @color_classes %{
    gray: "bg-gray-100 text-gray-700",
    green: "bg-green-100 text-green-700",
    red: "bg-red-100 text-red-700",
    blue: "bg-blue-100 text-blue-700",
    yellow: "bg-yellow-100 text-yellow-700"
  }

  attr :color, :atom, required: true, values: [:gray, :green, :red, :blue, :yellow]
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :title, :string, default: nil
  attr :spinner?, :boolean, default: false

  def status_badge(assigns) do
    assigns = assign(assigns, :color_class, Map.get(@color_classes, assigns.color, ""))

    ~H"""
    <span
      class={"inline-flex items-center #{if @spinner?, do: "gap-1.5 ", else: ""}px-2 py-0.5 rounded-full text-xs font-medium #{@color_class}"}
      title={@title}
    >
      <div :if={@spinner?} class="animate-spin rounded-full h-3 w-3 border-2 border-blue-400 border-t-transparent">
      </div>
      {badge_text(@label, @value)}
    </span>
    """
  end

  defp badge_text(label, nil), do: label
  defp badge_text(label, value), do: "#{label}: #{value}"
end

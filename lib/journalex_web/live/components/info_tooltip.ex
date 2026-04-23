defmodule JournalexWeb.InfoTooltip do
  use JournalexWeb, :html

  @moduledoc """
  Renders a small ⓘ icon with a CSS-only hover tooltip.

  Usage:
      <.info_tooltip text="Explanation of this section" />

  The tooltip appears above the icon on hover. No JavaScript required.
  """

  attr :text, :string, required: true
  attr :class, :string, default: ""

  def info_tooltip(assigns) do
    ~H"""
    <span class={"relative inline-flex items-center group #{@class}"}>
      <span class="ml-1 cursor-default text-zinc-400 hover:text-zinc-600 text-[11px] leading-none select-none">ⓘ</span>
      <span class="
        pointer-events-none
        absolute bottom-full left-1/2 -translate-x-1/2 mb-2
        w-56 rounded-md bg-zinc-900 px-3 py-2
        text-xs font-normal text-white leading-snug
        opacity-0 group-hover:opacity-100 transition-opacity duration-150
        z-50 shadow-lg whitespace-normal
      ">
        <%= @text %>
        <span class="absolute top-full left-1/2 -translate-x-1/2 border-4 border-transparent border-t-zinc-900"></span>
      </span>
    </span>
    """
  end
end

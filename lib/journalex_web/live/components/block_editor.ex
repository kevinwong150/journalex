defmodule JournalexWeb.BlockEditor do
  @moduledoc """
  Reusable block editor function component for writeup drafts.

  Renders a block list with per-block controls (type toggle, text editing,
  move up/down, add after, delete) plus add-at-end buttons.

  Events emitted (handled by the parent LiveView):
  - `add_block` with `type` and `after` params
  - `add_block_end` with `type` param
  - `delete_block` with `index` param
  - `move_block_up` / `move_block_down` with `index` param
  - `update_block_text` with `index` and `value` params
  - `toggle_block_type` with `index` param
  - `insert_preset_block_at` with `id` and `after` params
  """

  use JournalexWeb, :html

  attr :blocks, :list, required: true
  attr :preset_blocks, :list, default: []

  def block_editor(assigns) do
    ~H"""
    <div>
      <%= if @blocks == [] do %>
        <div class="text-center py-8 border-2 border-dashed border-zinc-200 rounded-lg">
          <p class="text-sm text-zinc-400 mb-3">No blocks yet. Add one or apply a preset.</p>
          <div class="flex items-center justify-center gap-2">
            <button
              type="button"
              phx-click="add_block_end"
              phx-value-type="paragraph"
              class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
            >
              + Paragraph
            </button>
            <button
              type="button"
              phx-click="add_block_end"
              phx-value-type="toggle"
              class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-violet-50 text-violet-700 hover:bg-violet-100 transition-colors"
            >
              + Toggle
            </button>
          </div>
        </div>
      <% else %>
        <div class="space-y-2">
          <%= for {block, idx} <- Enum.with_index(@blocks) do %>
            <div class={[
              "flex items-start gap-2 p-2.5 rounded-lg border transition-colors",
              if(block["type"] == "toggle",
                do: "bg-violet-50/50 border-violet-200",
                else: "bg-zinc-50 border-zinc-200"
              )
            ]}>
              <%!-- Block index + type badge --%>
              <div class="flex flex-col items-center gap-1 pt-1 shrink-0">
                <span class="text-[10px] text-zinc-400 font-mono">{idx + 1}</span>
                <button
                  type="button"
                  phx-click="toggle_block_type"
                  phx-value-index={idx}
                  title={"Click to toggle type (currently #{block["type"]})"}
                  class={[
                    "px-1.5 py-0.5 text-[10px] font-semibold rounded cursor-pointer transition-colors",
                    if(block["type"] == "toggle",
                      do: "bg-violet-200 text-violet-700 hover:bg-violet-300",
                      else: "bg-zinc-200 text-zinc-600 hover:bg-zinc-300"
                    )
                  ]}
                >
                  {if block["type"] == "toggle", do: "TGL", else: "TXT"}
                </button>
              </div>

              <%!-- Text input --%>
              <div class="flex-1 min-w-0">
                <%= if block["type"] == "toggle" do %>
                  <input
                    type="text"
                    value={block["text"] || ""}
                    phx-keyup="update_block_text"
                    phx-value-index={idx}
                    placeholder="Toggle title..."
                    class="w-full px-2.5 py-1.5 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  />
                  <div class="mt-1 ml-2">
                    <span class="text-[10px] text-violet-500 italic">
                      Children: empty (paste images in Notion after push)
                    </span>
                  </div>
                <% else %>
                  <textarea
                    phx-keyup="update_block_text"
                    phx-value-index={idx}
                    placeholder="Paragraph text... (empty = blank line)"
                    rows="2"
                    class="w-full px-2.5 py-1.5 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 resize-y"
                  ><%= block["text"] || "" %></textarea>
                <% end %>
              </div>

              <%!-- Action buttons --%>
              <div class="flex items-center gap-0.5 shrink-0 pt-1">
                <button
                  type="button"
                  phx-click="move_block_up"
                  phx-value-index={idx}
                  disabled={idx == 0}
                  class="p-1 rounded text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  title="Move up"
                >
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
                  </svg>
                </button>
                <button
                  type="button"
                  phx-click="move_block_down"
                  phx-value-index={idx}
                  disabled={idx == length(@blocks) - 1}
                  class="p-1 rounded text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  title="Move down"
                >
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                <%!-- Add block after --%>
                <div class="relative group">
                  <button
                    type="button"
                    class="p-1 rounded text-zinc-400 hover:text-green-600 hover:bg-green-50 transition-colors"
                    title="Add block after"
                  >
                    <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                  </button>
                  <div class="hidden group-hover:flex absolute right-0 top-full mt-0.5 bg-white border border-zinc-200 rounded-md shadow-lg z-10 flex-col py-1 min-w-[160px]">
                    <button
                      type="button"
                      phx-click="add_block"
                      phx-value-type="paragraph"
                      phx-value-after={idx}
                      class="px-3 py-1.5 text-xs text-left hover:bg-zinc-50 text-zinc-700"
                    >
                      + Paragraph
                    </button>
                    <button
                      type="button"
                      phx-click="add_block"
                      phx-value-type="toggle"
                      phx-value-after={idx}
                      class="px-3 py-1.5 text-xs text-left hover:bg-zinc-50 text-violet-700"
                    >
                      + Toggle
                    </button>
                    <%= if @preset_blocks != [] do %>
                      <div class="border-t border-zinc-100 my-1"></div>
                      <p class="px-3 py-1 text-[10px] font-semibold text-zinc-400 uppercase">Preset Blocks</p>
                      <%= for pb <- @preset_blocks do %>
                        <button
                          type="button"
                          phx-click="insert_preset_block_at"
                          phx-value-id={pb.id}
                          phx-value-after={idx}
                          class="px-3 py-1.5 text-xs text-left hover:bg-violet-50 text-violet-600 truncate"
                        >
                          + {pb.name} <span class="text-zinc-400">({length(pb.blocks)})</span>
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="delete_block"
                  phx-value-index={idx}
                  class="p-1 rounded text-zinc-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                  title="Delete block"
                >
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Add block at end --%>
        <div class="mt-3 flex items-center justify-center gap-2">
          <button
            type="button"
            phx-click="add_block_end"
            phx-value-type="paragraph"
            class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
          >
            + Paragraph
          </button>
          <button
            type="button"
            phx-click="add_block_end"
            phx-value-type="toggle"
            class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-md bg-violet-50 text-violet-700 hover:bg-violet-100 transition-colors"
          >
            + Toggle
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end

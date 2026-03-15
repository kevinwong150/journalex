defmodule JournalexWeb.WriteupDraftLive do
  @moduledoc """
  LiveView page for managing writeup draft templates.

  Two-column layout:
  - Left panel: list of saved writeup drafts (name, block count, Edit / Delete)
  - Right panel: block editor with preset templates and per-block controls
  """
  use JournalexWeb, :live_view

  alias Journalex.WriteupDrafts
  alias Journalex.WriteupDrafts.Draft

  @presets %{
    "standard" => %{
      label: "Standard Trade",
      blocks: [
        %{"type" => "toggle", "text" => "1min", "children" => []},
        %{"type" => "toggle", "text" => "2min", "children" => []},
        %{"type" => "toggle", "text" => "5min", "children" => []},
        %{"type" => "toggle", "text" => "15min", "children" => []},
        %{"type" => "toggle", "text" => "daily", "children" => []},
        %{"type" => "paragraph", "text" => ""},
        %{"type" => "paragraph", "text" => "Environment Overview:"},
        %{"type" => "paragraph", "text" => ""},
        %{"type" => "paragraph", "text" => "Comments:"}
      ]
    },
    "minimal" => %{
      label: "Minimal",
      blocks: [
        %{"type" => "paragraph", "text" => "Environment Overview:"},
        %{"type" => "paragraph", "text" => ""},
        %{"type" => "paragraph", "text" => "Comments:"}
      ]
    },
    "empty" => %{
      label: "Empty",
      blocks: []
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    WriteupDrafts.ensure_preset_draft()
    drafts = WriteupDrafts.list_drafts()

    socket =
      socket
      |> assign(:drafts, drafts)
      |> assign(:editing_draft, nil)
      |> assign(:draft_name, "")
      |> assign(:blocks, [])
      |> assign(:presets, @presets)
      |> assign(:select_mode, false)
      |> assign(:selected_ids, MapSet.new())

    {:ok, socket}
  end

  # ── Event handlers ──────────────────────────────────────────────────

  @impl true
  def handle_event("new_draft", _params, socket) do
    socket =
      socket
      |> assign(:editing_draft, nil)
      |> assign(:draft_name, "")
      |> assign(:blocks, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = WriteupDrafts.get_draft!(id)

    socket =
      socket
      |> assign(:editing_draft, draft)
      |> assign(:draft_name, draft.name)
      |> assign(:blocks, draft.blocks || [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = WriteupDrafts.get_draft!(id)

    if draft.is_preset do
      {:noreply, put_toast(socket, :error, "Preset draft cannot be deleted")}
    else
      case WriteupDrafts.delete_draft(draft) do
      {:ok, _} ->
        drafts = WriteupDrafts.list_drafts()

        editing = socket.assigns.editing_draft

        socket =
          if editing && editing.id == draft.id do
            socket
            |> assign(:editing_draft, nil)
            |> assign(:draft_name, "")
            |> assign(:blocks, [])
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:drafts, drafts)
         |> put_toast(:info, "Draft \"#{draft.name}\" deleted")}

      {:error, _} ->
        {:noreply, put_toast(socket, :error, "Failed to delete draft")}
    end
    end
  end

  @impl true
  def handle_event("duplicate_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = WriteupDrafts.get_draft!(id)

    new_name = draft.name <> " (copy)"

    case WriteupDrafts.create_draft(%{name: new_name, blocks: draft.blocks || []}) do
      {:ok, new_draft} ->
        drafts = WriteupDrafts.list_drafts()

        {:noreply,
         socket
         |> assign(:drafts, drafts)
         |> assign(:editing_draft, new_draft)
         |> assign(:draft_name, new_draft.name)
         |> assign(:blocks, new_draft.blocks || [])
         |> put_toast(:info, "Draft duplicated as \"#{new_name}\"")}

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_toast(socket, :error, "Failed to duplicate: #{errors}")}
    end
  end

  @impl true
  def handle_event("apply_preset", %{"preset" => preset_key}, socket) do
    case Map.get(@presets, preset_key) do
      %{label: label, blocks: fallback_blocks} ->
        # Use the DB preset draft's actual saved blocks for "standard";
        # fall back to the hardcoded blocks for other presets.
        blocks =
          if preset_key == "standard" do
            case Enum.find(socket.assigns.drafts, & &1.is_preset) do
              %{blocks: db_blocks} when is_list(db_blocks) -> db_blocks
              _ -> fallback_blocks
            end
          else
            fallback_blocks
          end

        # Always stay in new-draft mode — just populate the blocks as a starting point.
        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> put_toast(:info, "Applied \"#{label}\" preset")}

      nil ->
        {:noreply, put_toast(socket, :error, "Unknown preset")}
    end
  end

  @impl true
  def handle_event("save_draft", _params, socket) do
    name = String.trim(socket.assigns.draft_name)
    blocks = socket.assigns.blocks

    attrs = %{name: name, blocks: blocks}

    result =
      case socket.assigns.editing_draft do
        nil -> WriteupDrafts.create_draft(attrs)
        %Draft{} = draft -> WriteupDrafts.update_draft(draft, attrs)
      end

    case result do
      {:ok, saved_draft} ->
        drafts = WriteupDrafts.list_drafts()
        action = if socket.assigns.editing_draft, do: "updated", else: "created"

        {:noreply,
         socket
         |> assign(:drafts, drafts)
         |> assign(:editing_draft, saved_draft)
         |> assign(:draft_name, saved_draft.name)
         |> assign(:blocks, saved_draft.blocks || [])
         |> put_toast(:info, "Draft \"#{saved_draft.name}\" #{action}")}

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_toast(socket, :error, "Failed to save draft: #{errors}")}
    end
  end

  @impl true
  def handle_event("update_draft_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :draft_name, name)}
  end

  # ── Block editing events ────────────────────────────────────────────

  @impl true
  def handle_event("add_block", %{"type" => type, "after" => after_str}, socket) do
    {after_idx, _} = Integer.parse(after_str)
    new_block = new_block(type)
    blocks = List.insert_at(socket.assigns.blocks, after_idx + 1, new_block)
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("add_block_end", %{"type" => type}, socket) do
    new_block = new_block(type)
    blocks = socket.assigns.blocks ++ [new_block]
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("delete_block", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = List.delete_at(socket.assigns.blocks, idx)
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("move_block_up", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = socket.assigns.blocks

    if idx > 0 do
      blocks = swap(blocks, idx, idx - 1)
      {:noreply, assign(socket, :blocks, blocks)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_block_down", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = socket.assigns.blocks

    if idx < length(blocks) - 1 do
      blocks = swap(blocks, idx, idx + 1)
      {:noreply, assign(socket, :blocks, blocks)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_block_text", %{"index" => idx_str, "value" => value}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = List.update_at(socket.assigns.blocks, idx, &Map.put(&1, "text", value))
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("toggle_block_type", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)

    blocks =
      List.update_at(socket.assigns.blocks, idx, fn block ->
        case block["type"] do
          "paragraph" -> Map.put(block, "type", "toggle") |> Map.put_new("children", [])
          "toggle" -> block |> Map.put("type", "paragraph") |> Map.delete("children")
          _ -> block
        end
      end)

    {:noreply, assign(socket, :blocks, blocks)}
  end

  # ── Select mode ─────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_select_mode", _params, socket) do
    select_mode = !socket.assigns.select_mode

    socket =
      socket
      |> assign(:select_mode, select_mode)
      |> assign(:selected_ids, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_ids =
      socket.assigns.drafts
      |> Enum.reject(& &1.is_preset)
      |> Enum.map(& &1.id)
      |> MapSet.new()
    currently_selected = socket.assigns.selected_ids

    selected =
      if MapSet.equal?(currently_selected, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("delete_selected_drafts", _params, socket) do
    ids =
      socket.assigns.selected_ids
      |> MapSet.to_list()
      |> Enum.reject(fn id ->
        draft = Enum.find(socket.assigns.drafts, &(&1.id == id))
        draft && draft.is_preset
      end)

    results =
      Enum.map(ids, fn id ->
        draft = WriteupDrafts.get_draft!(id)
        WriteupDrafts.delete_draft(draft)
      end)

    deleted = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    drafts = WriteupDrafts.list_drafts()

    editing = socket.assigns.editing_draft

    socket =
      if editing && MapSet.member?(socket.assigns.selected_ids, editing.id) do
        socket
        |> assign(:editing_draft, nil)
        |> assign(:draft_name, "")
        |> assign(:blocks, [])
      else
        socket
      end

    flash_msg =
      if failed == 0,
        do: "Deleted #{deleted} draft(s)",
        else: "Deleted #{deleted}, failed to delete #{failed}"

    flash_level = if failed == 0, do: :info, else: :error

    {:noreply,
     socket
     |> assign(:drafts, drafts)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_mode, false)
     |> put_toast(flash_level, flash_msg)}
  end

  # ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto mt-8 px-4 pb-10">
      <%!-- Page header --%>
      <div class="mb-6 flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Writeup Drafts</h1>
          <p class="text-sm text-zinc-500 mt-1">
            Save and reuse block content templates for trade writeups.
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button
            phx-click="new_draft"
            class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-green-600 text-white hover:bg-green-700 transition-colors shadow-sm"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            New Draft
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
        <%!-- Left panel: Draft list --%>
        <div class="lg:col-span-1 sticky top-20">
          <div class="bg-white rounded-lg border border-zinc-200 shadow-sm overflow-hidden max-h-[calc(100vh-5.5rem)] flex flex-col">
            <div class="px-4 py-3 border-b border-zinc-100 bg-zinc-50 flex items-center justify-between">
              <h3 class="text-xs font-semibold text-zinc-600 uppercase tracking-wide">
                Saved Drafts
              </h3>
              <div class="flex items-center gap-2">
                <span :if={@select_mode && @drafts != []} class="text-xs text-zinc-500 cursor-pointer hover:text-zinc-800" phx-click="toggle_select_all">
                  {if MapSet.size(@selected_ids) == length(@drafts), do: "Deselect all", else: "Select all"}
                </span>
                <button
                  phx-click="toggle_select_mode"
                  class={[
                    "text-xs px-2 py-0.5 rounded-md border font-medium transition-colors",
                    if(@select_mode,
                      do: "bg-red-100 text-red-700 border-red-300 hover:bg-red-200",
                      else: "bg-zinc-100 text-zinc-600 border-zinc-200 hover:bg-zinc-200"
                    )
                  ]}
                >
                  {if @select_mode, do: "Cancel", else: "Select"}
                </button>
                <span class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-zinc-200 text-zinc-600">
                  {length(@drafts)}
                </span>
              </div>
            </div>

            <div class="overflow-y-auto flex-1">
              <%= if @drafts == [] do %>
                <div class="px-4 py-10 text-center">
                  <svg class="mx-auto w-8 h-8 text-zinc-300 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                  </svg>
                  <p class="text-sm text-zinc-400">No drafts yet.</p>
                  <p class="text-xs text-zinc-400 mt-0.5">Create one using the editor on the right.</p>
                </div>
              <% else %>
                <ul class="divide-y divide-zinc-100">
                  <%= for draft <- @drafts do %>
                    <li class={[
                      "px-3 py-3 transition-colors border-l-[3px]",
                      if(@editing_draft && @editing_draft.id == draft.id,
                        do: "bg-blue-100 border-blue-500 shadow-sm",
                        else: "border-transparent hover:bg-zinc-50"
                      )
                    ]}>
                      <div class="flex items-start justify-between gap-1.5">
                        <%!-- Checkbox (only in select mode, not for presets) --%>
                        <div :if={@select_mode && !draft.is_preset} class="flex items-center pt-0.5 mr-1 shrink-0">
                          <input
                            type="checkbox"
                            checked={MapSet.member?(@selected_ids, draft.id)}
                            phx-click="toggle_select_draft"
                            phx-value-id={draft.id}
                            class="w-4 h-4 rounded border-zinc-300 text-red-600 cursor-pointer"
                          />
                        </div>
                        <%!-- Spacer for preset in select mode --%>
                        <div :if={@select_mode && draft.is_preset} class="w-5 shrink-0"></div>
                        <div class="min-w-0 flex-1">
                          <div class="flex items-center gap-1.5">
                            <svg
                              :if={draft.inserted_at != draft.updated_at}
                              class="w-3 h-3 shrink-0 text-amber-400"
                              fill="currentColor"
                              viewBox="0 0 24 24"
                              title="Modified after creation"
                            >
                              <path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 000-1.41l-2.34-2.34a1 1 0 00-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/>
                            </svg>
                            <p class={[
                              "text-sm font-medium truncate",
                              if(@editing_draft && @editing_draft.id == draft.id,
                                do: "text-blue-700 font-semibold",
                                else: "text-zinc-900"
                              )
                            ]}>
                              {draft.name}
                            </p>
                          </div>
                          <div class="flex items-center gap-1.5 mt-1">
                            <span class="inline-flex items-center px-1.5 py-0.5 text-[10px] font-semibold rounded bg-violet-100 text-violet-700">
                              {length(draft.blocks || [])} blocks
                            </span>
                            <%= if draft.is_preset do %>
                              <span class="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-semibold rounded bg-amber-100 text-amber-700">
                                <svg class="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 24 24">
                                  <path d="M12 1a5 5 0 00-5 5v2H5a2 2 0 00-2 2v11a2 2 0 002 2h14a2 2 0 002-2V10a2 2 0 00-2-2h-2V6a5 5 0 00-5-5zm0 2a3 3 0 013 3v2H9V6a3 3 0 013-3zm0 9a2 2 0 110 4 2 2 0 010-4z"/>
                                </svg>
                                preset
                              </span>
                            <% end %>
                            <span class="text-[10px] text-zinc-400">
                              {Calendar.strftime(draft.updated_at, "%b %d, %H:%M")}
                            </span>
                          </div>
                        </div>
                        <div :if={!@select_mode} class="flex items-center gap-0.5 shrink-0">
                          <button
                            phx-click="edit_draft"
                            phx-value-id={draft.id}
                            class="p-1.5 rounded text-zinc-400 hover:text-blue-600 hover:bg-blue-50 transition-colors"
                            title="Edit"
                          >
                            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                            </svg>
                          </button>
                          <button
                            phx-click="duplicate_draft"
                            phx-value-id={draft.id}
                            class="p-1.5 rounded text-zinc-400 hover:text-green-600 hover:bg-green-50 transition-colors"
                            title="Duplicate"
                          >
                            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                            </svg>
                          </button>
                          <%= if draft.is_preset do %>
                            <span
                              class="p-1.5 rounded text-zinc-300 cursor-not-allowed"
                              title="Preset draft cannot be deleted"
                            >
                              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M12 1a5 5 0 00-5 5v2H5a2 2 0 00-2 2v11a2 2 0 002 2h14a2 2 0 002-2V10a2 2 0 00-2-2h-2V6a5 5 0 00-5-5zm0 2a3 3 0 013 3v2H9V6a3 3 0 013-3zm0 9a2 2 0 110 4 2 2 0 010-4z"/>
                              </svg>
                            </span>
                          <% else %>
                            <button
                              phx-click="delete_draft"
                              phx-value-id={draft.id}
                              class="p-1.5 rounded text-zinc-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                              title="Delete"
                              data-confirm={"Delete draft \"#{draft.name}\"?"}
                            >
                              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          <% end %>
                        </div>
                      </div>
                    </li>
                  <% end %>
                </ul>
                <%!-- Bulk delete footer --%>
                <div :if={@select_mode && MapSet.size(@selected_ids) > 0} class="px-3 py-2 border-t border-red-100 bg-red-50">
                  <button
                    phx-click="delete_selected_drafts"
                    data-confirm={"Delete #{MapSet.size(@selected_ids)} selected draft(s)? This cannot be undone."}
                    class="w-full inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-red-600 text-white hover:bg-red-700 transition-colors shadow-sm"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                    Delete {MapSet.size(@selected_ids)} selected
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Right panel: Block editor --%>
        <div class="lg:col-span-2">
          <div class="bg-white rounded-lg border border-zinc-200 shadow-sm">
            <div class="px-4 py-3 border-b border-zinc-100 bg-zinc-50">
              <div class="flex items-center justify-between">
                <h3 class="text-xs font-semibold text-zinc-600 uppercase tracking-wide">
                  {if @editing_draft, do: "Edit Draft — #{@editing_draft.name}", else: "New Draft"}
                </h3>
                <div class="flex items-center gap-1.5">
                  <span class="text-xs text-zinc-500 mr-1">Preset:</span>
                  <% db_preset = Enum.find(@drafts, & &1.is_preset) %>
                  <%= for {key, preset} <- @presets do %>
                    <button
                      type="button"
                      phx-click="apply_preset"
                      phx-value-preset={key}
                      class="px-2.5 py-1 text-xs font-medium rounded-md bg-zinc-100 text-zinc-600 hover:bg-zinc-200 transition-colors"
                    >
                      {if key == "standard" && db_preset, do: db_preset.name, else: preset.label}
                    </button>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="p-4 space-y-4">
              <%!-- Draft name input --%>
              <div>
                <label for="draft-name" class="block text-sm font-medium text-zinc-700 mb-1.5">
                  Draft Name
                </label>
                <input
                  type="text"
                  id="draft-name"
                  value={@draft_name}
                  phx-keyup="update_draft_name"
                  placeholder="e.g. Standard Trade Writeup"
                  class="w-full px-3 py-2 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <%!-- Block list --%>
              <div>
                <div class="flex items-center justify-between mb-2">
                  <label class="block text-sm font-medium text-zinc-700">
                    Blocks <span class="text-zinc-400 font-normal">({length(@blocks)})</span>
                  </label>
                </div>

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
                            <div class="hidden group-hover:flex absolute right-0 top-full mt-0.5 bg-white border border-zinc-200 rounded-md shadow-lg z-10 flex-col py-1 min-w-[120px]">
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

              <%!-- Save button --%>
              <div class="pt-2 border-t border-zinc-100">
                <button
                  type="button"
                  phx-click="save_draft"
                  class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors shadow-sm"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                  {if @editing_draft, do: "Update Draft", else: "Save Draft"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp new_block("toggle"), do: %{"type" => "toggle", "text" => "", "children" => []}
  defp new_block(_), do: %{"type" => "paragraph", "text" => ""}

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)

    list
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end
end

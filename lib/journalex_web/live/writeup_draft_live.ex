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
  alias Journalex.WriteupDrafts.PresetBlock
  alias Journalex.CombinedDrafts
  alias Journalex.MetadataDrafts

  @presets %{
    "empty" => %{
      label: "Empty",
      blocks: []
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    WriteupDrafts.ensure_preset_draft()
    drafts = WriteupDrafts.list_drafts()

    preset_blocks = WriteupDrafts.list_preset_blocks()
    preset_block_groups = WriteupDrafts.list_preset_block_groups()

    socket =
      socket
      |> assign(:drafts, drafts)
      |> assign(:editing_draft, nil)
      |> assign(:draft_name, "")
      |> assign(:blocks, [])
      |> assign(:presets, @presets)
      |> assign(:select_mode, false)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:preset_blocks, preset_blocks)
      |> assign(:preset_block_groups, preset_block_groups)
      |> assign(:drawer_open, false)
      |> assign(:drawer_mode, :list)
      |> assign(:editing_preset_block, nil)
      |> assign(:pb_name, "")
      |> assign(:pb_blocks, [])
      |> assign(:pb_group, "")
      |> assign(:collapsed_groups, MapSet.new())
      |> assign(:active_block_index, nil)
      |> assign(:import_preview, nil)
      # Combined drafts management
      |> assign(:combined_drafts, CombinedDrafts.list_drafts())
      |> assign(:all_metadata_drafts, MetadataDrafts.list_drafts())
      |> assign(:all_writeup_drafts, WriteupDrafts.list_drafts())
      |> assign(:cd_editing, nil)
      |> assign(:cd_name, "")
      |> assign(:cd_metadata_draft_id, nil)
      |> assign(:cd_writeup_draft_id, nil)
      |> assign(:cd_bulk_mode, false)
      |> assign(:cd_bulk_names, List.duplicate("", 2))
      |> assign(:cd_bulk_auto_meta, true)
      |> assign(:cd_bulk_auto_writeup, true)
      |> assign(:cd_bulk_version, Journalex.Settings.get_default_metadata_version())
      |> allow_upload(:import_json,
        accept: ~w(.json),
        max_entries: 1,
        max_file_size: 1_000_000,
        auto_upload: true
      )

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
  def handle_event("toggle_preset_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = WriteupDrafts.get_draft!(id)

    case WriteupDrafts.toggle_preset_draft(draft) do
      {:ok, updated} ->
        drafts = WriteupDrafts.list_drafts()
        msg = if updated.is_preset, do: "\"#{updated.name}\" marked as preset", else: "\"#{updated.name}\" removed from preset"

        socket =
          if socket.assigns.editing_draft && socket.assigns.editing_draft.id == updated.id do
            assign(socket, :editing_draft, updated)
          else
            socket
          end

        {:noreply, socket |> assign(:drafts, drafts) |> put_toast(:info, msg)}

      {:error, _} ->
        {:noreply, put_toast(socket, :error, "Failed to update preset flag")}
    end
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
      %{label: label, blocks: blocks} ->
        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> put_toast(:info, "Applied \"#{label}\" preset")}

      nil ->
        {:noreply, put_toast(socket, :error, "Unknown preset")}
    end
  end

  @impl true
  def handle_event("apply_preset_draft", %{"draft-id" => draft_id_str}, socket) do
    {draft_id, _} = Integer.parse(draft_id_str)

    case WriteupDrafts.get_draft(draft_id) do
      nil ->
        {:noreply, put_toast(socket, :error, "Draft not found")}

      draft ->
        {:noreply,
         socket
         |> assign(:blocks, draft.blocks || [])
         |> put_toast(:info, "Applied \"#{draft.name}\" preset")}
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
    {:noreply, socket |> assign(:blocks, blocks) |> assign(:active_block_index, after_idx + 1)}
  end

  @impl true
  def handle_event("add_block_end", %{"type" => type}, socket) do
    new_block = new_block(type)
    blocks = socket.assigns.blocks ++ [new_block]
    {:noreply, socket |> assign(:blocks, blocks) |> assign(:active_block_index, length(blocks) - 1)}
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
    {:noreply, socket |> assign(:blocks, blocks) |> assign(:active_block_index, idx)}
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

  # ── Preset block drawer ──────────────────────────────────────────────

  @impl true
  def handle_event("open_drawer", _params, socket) do
    preset_blocks = WriteupDrafts.list_preset_blocks()
    preset_block_groups = WriteupDrafts.list_preset_block_groups()

    {:noreply,
     socket
     |> assign(:preset_blocks, preset_blocks)
     |> assign(:preset_block_groups, preset_block_groups)
     |> assign(:drawer_open, true)
     |> assign(:drawer_mode, :list)}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_open, false)
     |> assign(:drawer_mode, :list)
     |> assign(:editing_preset_block, nil)
     |> assign(:pb_name, "")
     |> assign(:pb_blocks, [])
     |> assign(:pb_group, "")}
  end

  @impl true
  def handle_event("drawer_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_mode, :new)
     |> assign(:editing_preset_block, nil)
     |> assign(:pb_name, "")
     |> assign(:pb_blocks, [])
     |> assign(:pb_group, "")}
  end

  @impl true
  def handle_event("drawer_edit", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    pb = WriteupDrafts.get_preset_block!(id)

    {:noreply,
     socket
     |> assign(:drawer_mode, :edit)
     |> assign(:editing_preset_block, pb)
     |> assign(:pb_name, pb.name)
     |> assign(:pb_blocks, pb.blocks || [])
     |> assign(:pb_group, pb.group || "")}
  end

  @impl true
  def handle_event("drawer_back", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_mode, :list)
     |> assign(:editing_preset_block, nil)
     |> assign(:pb_name, "")
     |> assign(:pb_blocks, [])
     |> assign(:pb_group, "")}
  end

  @impl true
  def handle_event("update_pb_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :pb_name, name)}
  end

  @impl true
  def handle_event("update_pb_group", %{"value" => group}, socket) do
    {:noreply, assign(socket, :pb_group, group)}
  end

  @impl true
  def handle_event("toggle_group_collapse", %{"group" => group}, socket) do
    collapsed =
      if MapSet.member?(socket.assigns.collapsed_groups, group) do
        MapSet.delete(socket.assigns.collapsed_groups, group)
      else
        MapSet.put(socket.assigns.collapsed_groups, group)
      end

    {:noreply, assign(socket, :collapsed_groups, collapsed)}
  end

  @impl true
  def handle_event("export_all", _params, socket) do
    data = WriteupDrafts.export_all() |> Jason.encode!(pretty: true)
    {:noreply, push_event(socket, "download_json", %{data: data, filename: "writeup_drafts_export.json"})}
  end

  @impl true
  def handle_event("validate_import_json", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("parse_import_json", _params, socket) do
    results =
      consume_uploaded_entries(socket, :import_json, fn %{path: path}, _entry ->
        content = File.read!(path)

        case Jason.decode(content) do
          {:ok, %{"drafts" => drafts, "preset_blocks" => pbs}}
              when is_list(drafts) and is_list(pbs) ->
            {:ok, {:ok, %{drafts: drafts, preset_blocks: pbs}}}

          {:ok, pbs} when is_list(pbs) ->
            # Legacy format: just an array of preset blocks
            {:ok, {:ok, %{drafts: [], preset_blocks: pbs}}}

          {:ok, _} ->
            {:ok, {:error, "Unrecognized JSON format"}}

          {:error, _} ->
            {:ok, {:error, "Invalid JSON file"}}
        end
      end)

    case results do
      [{:ok, preview}] ->
        {:noreply, assign(socket, :import_preview, preview)}

      [{:error, msg}] ->
        {:noreply, put_toast(socket, :error, msg)}

      _ ->
        {:noreply, put_toast(socket, :error, "Please select a JSON file to import")}
    end
  end

  @impl true
  def handle_event("confirm_import", _params, socket) do
    preview = socket.assigns.import_preview

    {draft_msg, socket} =
      case preview.drafts do
        [] ->
          {"", socket}

        entries ->
          {:ok, %{imported: imp, skipped: skip}} = WriteupDrafts.import_drafts(entries)
          drafts = WriteupDrafts.list_drafts()
          {"#{imp} draft(s) imported, #{skip} skipped", assign(socket, :drafts, drafts)}
      end

    {pb_msg, socket} =
      case preview.preset_blocks do
        [] ->
          {"", socket}

        entries ->
          {:ok, %{imported: imp, skipped: skip}} = WriteupDrafts.import_preset_blocks(entries)
          preset_blocks = WriteupDrafts.list_preset_blocks()
          preset_block_groups = WriteupDrafts.list_preset_block_groups()

          socket =
            socket
            |> assign(:preset_blocks, preset_blocks)
            |> assign(:preset_block_groups, preset_block_groups)

          {"#{imp} preset block(s) imported, #{skip} skipped", socket}
      end

    msg =
      [draft_msg, pb_msg]
      |> Enum.reject(& &1 == "")
      |> Enum.join(". ")

    {:noreply,
     socket
     |> assign(:import_preview, nil)
     |> put_toast(:info, if(msg == "", do: "Nothing to import", else: msg))}
  end

  @impl true
  def handle_event("cancel_import", _params, socket) do
    {:noreply, assign(socket, :import_preview, nil)}
  end

  @impl true
  def handle_event("save_preset_block", _params, socket) do
    group = case String.trim(socket.assigns.pb_group) do
      "" -> nil
      g -> g
    end

    attrs = %{
      name: String.trim(socket.assigns.pb_name),
      blocks: socket.assigns.pb_blocks,
      group: group
    }

    result =
      case socket.assigns.editing_preset_block do
        nil -> WriteupDrafts.create_preset_block(attrs)
        %PresetBlock{} = pb -> WriteupDrafts.update_preset_block(pb, attrs)
      end

    case result do
      {:ok, _saved} ->
        preset_blocks = WriteupDrafts.list_preset_blocks()
        preset_block_groups = WriteupDrafts.list_preset_block_groups()
        action = if socket.assigns.editing_preset_block, do: "updated", else: "created"

        {:noreply,
         socket
         |> assign(:preset_blocks, preset_blocks)
         |> assign(:preset_block_groups, preset_block_groups)
         |> assign(:drawer_mode, :list)
         |> assign(:editing_preset_block, nil)
         |> assign(:pb_name, "")
         |> assign(:pb_blocks, [])
         |> assign(:pb_group, "")
         |> put_toast(:info, "Preset block #{action}")}

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_toast(socket, :error, "Failed to save: #{errors}")}
    end
  end

  @impl true
  def handle_event("delete_preset_block", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    pb = WriteupDrafts.get_preset_block!(id)

    case WriteupDrafts.delete_preset_block(pb) do
      {:ok, _} ->
        preset_blocks = WriteupDrafts.list_preset_blocks()

        {:noreply,
         socket
         |> assign(:preset_blocks, preset_blocks)
         |> put_toast(:info, "Preset block \"#{pb.name}\" deleted")}

      {:error, _} ->
        {:noreply, put_toast(socket, :error, "Failed to delete preset block")}
    end
  end

  @impl true
  def handle_event("save_blocks_as_preset", _params, socket) do
    {:noreply,
     socket
     |> assign(:drawer_open, true)
     |> assign(:drawer_mode, :new)
     |> assign(:editing_preset_block, nil)
     |> assign(:pb_name, "")
     |> assign(:pb_blocks, socket.assigns.blocks)
     |> assign(:pb_group, "")
     |> assign(:preset_blocks, WriteupDrafts.list_preset_blocks())
     |> assign(:preset_block_groups, WriteupDrafts.list_preset_block_groups())}
  end

  # ── Drawer block editing events ─────────────────────────────────────

  @impl true
  def handle_event("pb_add_block", %{"type" => type}, socket) do
    new_block = new_block(type)
    blocks = socket.assigns.pb_blocks ++ [new_block]
    {:noreply, assign(socket, :pb_blocks, blocks)}
  end

  @impl true
  def handle_event("pb_delete_block", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = List.delete_at(socket.assigns.pb_blocks, idx)
    {:noreply, assign(socket, :pb_blocks, blocks)}
  end

  @impl true
  def handle_event("pb_update_block_text", %{"index" => idx_str, "value" => value}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = List.update_at(socket.assigns.pb_blocks, idx, &Map.put(&1, "text", value))
    {:noreply, assign(socket, :pb_blocks, blocks)}
  end

  @impl true
  def handle_event("pb_toggle_block_type", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)

    blocks =
      List.update_at(socket.assigns.pb_blocks, idx, fn block ->
        case block["type"] do
          "paragraph" -> Map.put(block, "type", "toggle") |> Map.put_new("children", [])
          "toggle" -> block |> Map.put("type", "paragraph") |> Map.delete("children")
          _ -> block
        end
      end)

    {:noreply, assign(socket, :pb_blocks, blocks)}
  end

  @impl true
  def handle_event("pb_move_block_up", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)

    if idx > 0 do
      blocks = swap(socket.assigns.pb_blocks, idx, idx - 1)
      {:noreply, assign(socket, :pb_blocks, blocks)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("pb_move_block_down", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)

    if idx < length(socket.assigns.pb_blocks) - 1 do
      blocks = swap(socket.assigns.pb_blocks, idx, idx + 1)
      {:noreply, assign(socket, :pb_blocks, blocks)}
    else
      {:noreply, socket}
    end
  end

  # ── Preset block insertion ─────────────────────────────────────────

  @impl true
  def handle_event("insert_preset_block", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    pb = WriteupDrafts.get_preset_block!(id)
    insert_idx = max((socket.assigns.active_block_index || length(socket.assigns.blocks) - 1) + 1, 0)

    {before, after_part} = Enum.split(socket.assigns.blocks, insert_idx)
    blocks = before ++ (pb.blocks || []) ++ after_part
    new_active = insert_idx + length(pb.blocks || []) - 1

    {:noreply,
     socket
     |> assign(:blocks, blocks)
     |> assign(:active_block_index, if(new_active >= 0, do: new_active, else: nil))
     |> put_toast(:info, "Inserted #{length(pb.blocks || [])} block(s) from \"#{pb.name}\"")}
  end

  @impl true
  def handle_event("insert_preset_block_at", %{"id" => id_str, "after" => after_str}, socket) do
    {id, _} = Integer.parse(id_str)
    {after_idx, _} = Integer.parse(after_str)
    pb = WriteupDrafts.get_preset_block!(id)

    insert_idx = after_idx + 1
    {before, after_part} = Enum.split(socket.assigns.blocks, insert_idx)
    blocks = before ++ (pb.blocks || []) ++ after_part

    new_active = insert_idx + length(pb.blocks || []) - 1

    {:noreply,
     socket
     |> assign(:blocks, blocks)
     |> assign(:active_block_index, if(new_active >= 0, do: new_active, else: nil))
     |> put_toast(:info, "Inserted #{length(pb.blocks || [])} block(s) from \"#{pb.name}\"")}
  end

  # ── Combined Drafts event handlers ──────────────────────────────────

  @impl true
  def handle_event("cd_update_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :cd_name, value)}
  end

  @impl true
  def handle_event("cd_select_metadata_draft", %{"value" => value}, socket) do
    id = if value == "", do: nil, else: String.to_integer(value)
    {:noreply, assign(socket, :cd_metadata_draft_id, id)}
  end

  @impl true
  def handle_event("cd_select_writeup_draft", %{"value" => value}, socket) do
    id = if value == "", do: nil, else: String.to_integer(value)
    {:noreply, assign(socket, :cd_writeup_draft_id, id)}
  end

  @impl true
  def handle_event("cd_save", _params, socket) do
    attrs = %{
      name: socket.assigns.cd_name,
      metadata_draft_id: socket.assigns.cd_metadata_draft_id,
      writeup_draft_id: socket.assigns.cd_writeup_draft_id
    }

    result =
      if socket.assigns.cd_editing do
        CombinedDrafts.update_draft(socket.assigns.cd_editing, attrs)
      else
        CombinedDrafts.create_draft(attrs)
      end

    case result do
      {:ok, _draft} ->
        action = if socket.assigns.cd_editing, do: "Updated", else: "Created"

        {:noreply,
         socket
         |> assign(:combined_drafts, CombinedDrafts.list_drafts())
         |> assign(:cd_editing, nil)
         |> assign(:cd_name, "")
         |> assign(:cd_metadata_draft_id, nil)
         |> assign(:cd_writeup_draft_id, nil)
         |> put_toast(:info, "#{action} combined draft")}

      {:error, changeset} ->
        msg =
          changeset.errors
          |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end)
          |> Enum.join(", ")

        {:noreply, put_toast(socket, :error, "Failed: #{msg}")}
    end
  end

  @impl true
  def handle_event("cd_edit", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = CombinedDrafts.get_draft!(id)

    {:noreply,
     socket
     |> assign(:cd_editing, draft)
     |> assign(:cd_name, draft.name)
     |> assign(:cd_metadata_draft_id, draft.metadata_draft_id)
     |> assign(:cd_writeup_draft_id, draft.writeup_draft_id)}
  end

  @impl true
  def handle_event("cd_cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:cd_editing, nil)
     |> assign(:cd_name, "")
     |> assign(:cd_metadata_draft_id, nil)
     |> assign(:cd_writeup_draft_id, nil)}
  end

  @impl true
  def handle_event("cd_delete", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = CombinedDrafts.get_draft!(id)

    case CombinedDrafts.delete_draft(draft) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:combined_drafts, CombinedDrafts.list_drafts())
         |> put_toast(:info, "Deleted combined draft \"#{draft.name}\"")}

      {:error, _} ->
        {:noreply, put_toast(socket, :error, "Failed to delete combined draft")}
    end
  end

  @impl true
  def handle_event("cd_toggle_bulk", _params, socket) do
    {:noreply,
     socket
     |> assign(:cd_bulk_mode, !socket.assigns.cd_bulk_mode)
     |> assign(:cd_bulk_names, List.duplicate("", 2))
     |> assign(:cd_bulk_auto_meta, true)
     |> assign(:cd_bulk_auto_writeup, true)
     |> assign(:cd_bulk_version, Journalex.Settings.get_default_metadata_version())}
  end

  @impl true
  def handle_event("cd_bulk_toggle_auto_meta", _params, socket) do
    {:noreply, assign(socket, :cd_bulk_auto_meta, !socket.assigns.cd_bulk_auto_meta)}
  end

  @impl true
  def handle_event("cd_bulk_toggle_auto_writeup", _params, socket) do
    {:noreply, assign(socket, :cd_bulk_auto_writeup, !socket.assigns.cd_bulk_auto_writeup)}
  end

  @impl true
  def handle_event("cd_bulk_set_version", %{"value" => v}, socket) do
    {:noreply, assign(socket, :cd_bulk_version, String.to_integer(v))}
  end

  @impl true
  def handle_event("cd_bulk_update_name", %{"value" => value, "index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    names = List.replace_at(socket.assigns.cd_bulk_names, idx, value)
    {:noreply, assign(socket, :cd_bulk_names, names)}
  end

  @impl true
  def handle_event("cd_bulk_add_row", _params, socket) do
    {:noreply, assign(socket, :cd_bulk_names, socket.assigns.cd_bulk_names ++ [""])}
  end

  @impl true
  def handle_event("cd_bulk_remove_row", _params, socket) do
    names = socket.assigns.cd_bulk_names
    {:noreply, assign(socket, :cd_bulk_names, Enum.take(names, max(length(names) - 1, 1)))}
  end

  @impl true
  def handle_event("cd_bulk_create", _params, socket) do
    names =
      socket.assigns.cd_bulk_names
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if names == [] do
      {:noreply, put_toast(socket, :error, "Please enter at least one name")}
    else
      auto_meta = socket.assigns.cd_bulk_auto_meta
      auto_writeup = socket.assigns.cd_bulk_auto_writeup
      version = socket.assigns.cd_bulk_version

      results =
        Enum.map(names, fn name ->
          md_id =
            if auto_meta do
              case MetadataDrafts.create_draft(%{name: name, metadata_version: version, metadata: %{}}) do
                {:ok, md} -> md.id
                {:error, _} -> nil
              end
            end

          wd_id =
            if auto_writeup do
              case WriteupDrafts.create_draft(%{name: name, blocks: []}) do
                {:ok, wd} -> wd.id
                {:error, _} -> nil
              end
            end

          CombinedDrafts.create_draft(%{
            name: name,
            metadata_draft_id: md_id,
            writeup_draft_id: wd_id
          })
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))
      created = Enum.count(results, &match?({:ok, _}, &1))

      parts =
        [if(auto_meta, do: "metadata V#{version}"), if(auto_writeup, do: "writeup")]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" + ")

      suffix = if parts != "", do: " with #{parts} drafts", else: ""

      socket =
        if errors == [] do
          socket
          |> assign(:combined_drafts, CombinedDrafts.list_drafts())
          |> assign(:all_metadata_drafts, MetadataDrafts.list_drafts())
          |> assign(:all_writeup_drafts, WriteupDrafts.list_drafts())
          |> assign(:drafts, WriteupDrafts.list_drafts())
          |> assign(:cd_bulk_mode, false)
          |> assign(:cd_bulk_names, List.duplicate("", 2))
          |> put_toast(:info, "Created #{created} combined draft(s)#{suffix}")
        else
          failed =
            Enum.map(errors, fn {:error, cs} ->
              cs.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")
            end)

          socket
          |> assign(:combined_drafts, CombinedDrafts.list_drafts())
          |> assign(:all_metadata_drafts, MetadataDrafts.list_drafts())
          |> assign(:all_writeup_drafts, WriteupDrafts.list_drafts())
          |> assign(:drafts, WriteupDrafts.list_drafts())
          |> put_toast(:error, "#{created} created; #{length(errors)} failed: #{Enum.join(failed, " | ")}")
        end

      {:noreply, socket}
    end
  end

  # ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div id="writeup-draft-page" phx-hook="DownloadJSON" class="max-w-6xl mx-auto mt-8 px-4 pb-10">
      <%!-- Page header --%>
      <div class="mb-6 flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Writeup Drafts</h1>
          <p class="text-sm text-zinc-500 mt-1">
            Save and reuse block content templates for trade writeups.
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <%!-- Export --%>
          <button
            phx-click="export_all"
            class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-zinc-100 text-zinc-700 hover:bg-zinc-200 transition-colors"
            title="Export drafts & preset blocks as JSON"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
            Export
          </button>
          <%!-- Import --%>
          <form phx-change="validate_import_json" phx-submit="parse_import_json">
            <label
              class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-zinc-100 text-zinc-700 hover:bg-zinc-200 transition-colors cursor-pointer"
              title="Import drafts & preset blocks from JSON"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
              </svg>
              Import
              <.live_file_input upload={@uploads.import_json} class="hidden" />
            </label>
            <button
              :if={@uploads.import_json.entries != []}
              type="submit"
              class="mt-1 inline-flex items-center justify-center px-3 py-1.5 rounded-md text-xs font-medium bg-green-100 text-green-700 hover:bg-green-200 transition-colors"
            >
              Preview &amp; Import
            </button>
          </form>
          <button
            phx-click="open_drawer"
            class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-violet-600 text-white hover:bg-violet-700 transition-colors shadow-sm"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
            </svg>
            Preset Blocks
            <span :if={@preset_blocks != []} class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-violet-500 text-white">
              {length(@preset_blocks)}
            </span>
          </button>
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
                          <button
                            phx-click="toggle_preset_draft"
                            phx-value-id={draft.id}
                            class={[
                              "p-1.5 rounded transition-colors",
                              if(draft.is_preset,
                                do: "text-amber-500 bg-amber-50 hover:bg-amber-100",
                                else: "text-zinc-400 hover:text-amber-500 hover:bg-amber-50"
                              )
                            ]}
                            title={if draft.is_preset, do: "Remove preset mark", else: "Mark as preset"}
                          >
                            <svg class="w-3.5 h-3.5" fill={if draft.is_preset, do: "currentColor", else: "none"} stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
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
                  <%= for {key, preset} <- @presets do %>
                    <button
                      type="button"
                      phx-click="apply_preset"
                      phx-value-preset={key}
                      class="px-2.5 py-1 text-xs font-medium rounded-md bg-zinc-100 text-zinc-600 hover:bg-zinc-200 transition-colors"
                    >
                      {preset.label}
                    </button>
                  <% end %>
                  <%= for draft <- Enum.filter(@drafts, & &1.is_preset) do %>
                    <button
                      type="button"
                      phx-click="apply_preset_draft"
                      phx-value-draft-id={draft.id}
                      class="px-2.5 py-1 text-xs font-medium rounded-md bg-violet-100 text-violet-700 hover:bg-violet-200 transition-colors"
                      title={"#{length(draft.blocks || [])} blocks"}
                    >
                      {draft.name}
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

              <%!-- Save button --%>
              <div class="pt-2 border-t border-zinc-100 flex items-center gap-2">
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
                <button
                  :if={@blocks != []}
                  type="button"
                  phx-click="save_blocks_as_preset"
                  class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-violet-100 text-violet-700 rounded-md hover:bg-violet-200 transition-colors"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                  </svg>
                  Save as Preset Block
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <%!-- ═══════ Combined Drafts Management ═══════ --%>
    <div class="mt-8 bg-white rounded-lg border border-sky-200 shadow-sm overflow-hidden">
      <div class="px-5 py-3 bg-sky-50 border-b border-sky-100 flex items-center justify-between">
        <div>
          <h2 class="text-sm font-semibold text-sky-800 uppercase tracking-wide">Combined Drafts</h2>
          <p class="text-xs text-sky-600 mt-0.5">Pair a metadata draft + writeup draft for one-click apply on Trades Dump.</p>
        </div>
        <div class="flex items-center gap-2">
          <button
            :if={!@cd_bulk_mode}
            phx-click="cd_toggle_bulk"
            class="text-xs px-2 py-1 rounded-md border border-sky-200 bg-sky-100 text-sky-700 hover:bg-sky-200 font-medium transition-colors"
          >
            Bulk create
          </button>
          <span class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-sky-200 text-sky-700">
            {length(@combined_drafts)}
          </span>
        </div>
      </div>

      <%!-- Bulk create form --%>
      <div :if={@cd_bulk_mode} class="px-5 py-4 border-b border-sky-100 bg-sky-50/50">
        <div class="flex items-center justify-between mb-3">
          <h4 class="text-xs font-semibold text-sky-700">Bulk Create Combined Drafts</h4>
          <button phx-click="cd_toggle_bulk" class="text-xs text-sky-600 hover:text-sky-800">Cancel</button>
        </div>
        <%!-- Auto-create options --%>
        <div class="flex flex-wrap items-center gap-4 mb-3 px-3 py-2 bg-white rounded-md border border-sky-200">
          <span class="text-[10px] font-semibold text-sky-700 uppercase tracking-wide">Auto-create:</span>
          <label class="inline-flex items-center gap-1.5 cursor-pointer">
            <button
              type="button"
              phx-click="cd_bulk_toggle_auto_meta"
              class={[
                "relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors",
                if(@cd_bulk_auto_meta, do: "bg-amber-500", else: "bg-zinc-300")
              ]}
            >
              <span class={[
                "pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform",
                if(@cd_bulk_auto_meta, do: "translate-x-4", else: "translate-x-0")
              ]} />
            </button>
            <span class="text-xs font-medium text-amber-700">Metadata Draft</span>
          </label>
          <label class="inline-flex items-center gap-1.5 cursor-pointer">
            <button
              type="button"
              phx-click="cd_bulk_toggle_auto_writeup"
              class={[
                "relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors",
                if(@cd_bulk_auto_writeup, do: "bg-violet-500", else: "bg-zinc-300")
              ]}
            >
              <span class={[
                "pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform",
                if(@cd_bulk_auto_writeup, do: "translate-x-4", else: "translate-x-0")
              ]} />
            </button>
            <span class="text-xs font-medium text-violet-700">Writeup Draft</span>
          </label>
          <div :if={@cd_bulk_auto_meta} class="inline-flex items-center gap-1.5">
            <span class="text-[10px] text-amber-600 font-medium">Version:</span>
            <select
              phx-change="cd_bulk_set_version"
              class="px-1.5 py-0.5 text-xs border border-amber-200 rounded focus:outline-none focus:ring-1 focus:ring-amber-400"
            >
              <option value="1" selected={@cd_bulk_version == 1}>V1</option>
              <option value="2" selected={@cd_bulk_version == 2}>V2</option>
            </select>
          </div>
        </div>
        <div class="space-y-2">
          <%= for {name, i} <- Enum.with_index(@cd_bulk_names) do %>
            <div class="flex items-center gap-2">
              <span class="text-[10px] text-sky-500 font-mono w-4 text-right shrink-0">{i + 1}</span>
              <input
                type="text"
                value={name}
                phx-keyup="cd_bulk_update_name"
                phx-value-index={i}
                placeholder="Combined draft name..."
                class="flex-1 px-2 py-1.5 text-sm border border-sky-200 rounded-md focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-sky-500"
              />
            </div>
          <% end %>
        </div>
        <div class="flex items-center justify-between mt-3">
          <div class="flex items-center gap-2">
            <button
              phx-click="cd_bulk_add_row"
              class="text-xs px-2 py-1 rounded border border-sky-200 text-sky-600 hover:bg-sky-100"
            >
              + Row
            </button>
            <button
              :if={length(@cd_bulk_names) > 1}
              phx-click="cd_bulk_remove_row"
              class="text-xs px-2 py-1 rounded border border-sky-200 text-sky-600 hover:bg-sky-100"
            >
              − Row
            </button>
          </div>
          <button
            phx-click="cd_bulk_create"
            class="px-3 py-1.5 text-xs font-medium bg-sky-600 text-white rounded-md hover:bg-sky-700 transition-colors shadow-sm"
          >
            Create {length(@cd_bulk_names)} combined draft(s)
          </button>
        </div>
      </div>

      <%!-- Inline create / edit form --%>
      <div class="px-5 py-4 border-b border-sky-100">
        <div class="flex items-center gap-2 mb-2">
          <h4 class="text-xs font-semibold text-sky-700">
            {if @cd_editing, do: "Edit Combined Draft", else: "New Combined Draft"}
          </h4>
          <button :if={@cd_editing} phx-click="cd_cancel_edit" class="text-xs text-sky-600 hover:text-sky-800">Cancel</button>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div>
            <label class="text-[10px] font-medium text-sky-600 uppercase tracking-wide">Name</label>
            <input
              type="text"
              value={@cd_name}
              phx-keyup="cd_update_name"
              placeholder="Combined draft name..."
              class="w-full mt-0.5 px-2 py-1.5 text-sm border border-sky-200 rounded-md focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-sky-500"
            />
          </div>
          <div>
            <label class="text-[10px] font-medium text-amber-600 uppercase tracking-wide">Metadata Draft</label>
            <select
              phx-change="cd_select_metadata_draft"
              class="w-full mt-0.5 px-2 py-1.5 text-sm border border-sky-200 rounded-md focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-sky-500"
            >
              <option value="">— None —</option>
              <%= for {version, version_drafts} <- Enum.group_by(@all_metadata_drafts, & &1.metadata_version) |> Enum.sort_by(&elem(&1, 0)) do %>
                <optgroup label={"V#{version}"}>
                  <%= for md <- version_drafts do %>
                    <option value={md.id} selected={@cd_metadata_draft_id == md.id}>{md.name}</option>
                  <% end %>
                </optgroup>
              <% end %>
            </select>
          </div>
          <div>
            <label class="text-[10px] font-medium text-violet-600 uppercase tracking-wide">Writeup Draft</label>
            <select
              phx-change="cd_select_writeup_draft"
              class="w-full mt-0.5 px-2 py-1.5 text-sm border border-sky-200 rounded-md focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-sky-500"
            >
              <option value="">— None —</option>
              <%= for wd <- @all_writeup_drafts do %>
                <option value={wd.id} selected={@cd_writeup_draft_id == wd.id}>{wd.name} ({length(wd.blocks || [])} blocks)</option>
              <% end %>
            </select>
          </div>
        </div>
        <div class="mt-3 flex justify-end">
          <button
            phx-click="cd_save"
            class="px-4 py-1.5 text-xs font-medium bg-sky-600 text-white rounded-md hover:bg-sky-700 transition-colors shadow-sm"
          >
            {if @cd_editing, do: "Update", else: "Create"}
          </button>
        </div>
      </div>

      <%!-- List --%>
      <div :if={@combined_drafts == []} class="px-5 py-6 text-center text-sm text-sky-400">
        No combined drafts yet. Create one above.
      </div>
      <ul :if={@combined_drafts != []} class="divide-y divide-sky-100">
        <%= for cd <- @combined_drafts do %>
          <li class="px-5 py-3 flex items-center justify-between gap-3 hover:bg-sky-50/50 transition-colors">
            <div class="min-w-0 flex-1">
              <p class="text-sm font-medium text-zinc-900 truncate">{cd.name}</p>
              <div class="flex items-center gap-2 mt-0.5">
                <span :if={cd.metadata_draft} class="inline-flex items-center gap-1 text-[10px] font-medium text-amber-700 bg-amber-50 px-1.5 py-0.5 rounded">
                  <span class="w-1.5 h-1.5 rounded-full bg-amber-400"></span>
                  {cd.metadata_draft.name} (V{cd.metadata_draft.metadata_version})
                </span>
                <span :if={is_nil(cd.metadata_draft)} class="text-[10px] text-zinc-400 italic">no metadata</span>
                <span :if={cd.writeup_draft} class="inline-flex items-center gap-1 text-[10px] font-medium text-violet-700 bg-violet-50 px-1.5 py-0.5 rounded">
                  <span class="w-1.5 h-1.5 rounded-full bg-violet-400"></span>
                  {cd.writeup_draft.name} ({length(cd.writeup_draft.blocks || [])} blk)
                </span>
                <span :if={is_nil(cd.writeup_draft)} class="text-[10px] text-zinc-400 italic">no writeup</span>
              </div>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <button
                phx-click="cd_edit"
                phx-value-id={cd.id}
                class="p-1.5 rounded text-zinc-400 hover:text-sky-600 hover:bg-sky-50 transition-colors"
                title="Edit"
              >
                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
              </button>
              <button
                phx-click="cd_delete"
                phx-value-id={cd.id}
                class="p-1.5 rounded text-zinc-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                title="Delete"
                data-confirm={"Delete combined draft \"#{cd.name}\"?"}
              >
                <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            </div>
          </li>
        <% end %>
      </ul>
    </div>

    <%!-- Import Preview Modal --%>
    <div
      :if={@import_preview}
      class="fixed inset-0 z-50 flex items-center justify-center"
      phx-window-keydown="cancel_import"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-zinc-900/65" phx-click="cancel_import"></div>
      <div class="relative bg-white rounded-xl shadow-2xl ring-1 ring-black/15 w-full max-w-lg mx-4 max-h-[80vh] flex flex-col overflow-hidden">
        <%!-- Coloured top accent bar --%>
        <div class="h-1 w-full bg-gradient-to-r from-blue-500 via-violet-500 to-violet-400 shrink-0"></div>
        <%!-- Header --%>
        <div class="px-5 py-4 border-b border-zinc-200 bg-white flex items-center justify-between shrink-0">
          <h3 class="text-base font-semibold text-zinc-900">Import Preview</h3>
          <button type="button" phx-click="cancel_import" class="p-1.5 rounded text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 transition-colors">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%!-- Body --%>
        <div class="flex-1 overflow-y-auto p-5 space-y-5">
          <%!-- Preset Drafts section --%>
          <div>
            <h4 class="text-sm font-semibold text-zinc-700 mb-2 flex items-center gap-2">
              <svg class="w-4 h-4 text-amber-500" fill="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
              </svg>
              Preset Drafts
              <span class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-amber-100 text-amber-700">
                {length(@import_preview.drafts)}
              </span>
            </h4>
            <%= if @import_preview.drafts == [] do %>
              <p class="text-xs text-zinc-400 italic">No preset drafts in this file.</p>
            <% else %>
              <div class="space-y-1.5">
                <%= for entry <- @import_preview.drafts do %>
                  <%
                    name = entry["name"] || entry[:name] || "(unnamed)"
                    blocks = entry["blocks"] || entry[:blocks] || []
                  %>
                  <div class="flex items-center justify-between gap-2 px-3 py-2 bg-zinc-50 border border-zinc-200 rounded-lg">
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-zinc-900 truncate">{name}</p>
                      <span class="text-[10px] text-zinc-400">{length(blocks)} blocks</span>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Preset Blocks section --%>
          <div>
            <h4 class="text-sm font-semibold text-zinc-700 mb-2 flex items-center gap-2">
              <svg class="w-4 h-4 text-violet-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
              </svg>
              Preset Blocks
              <span class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-violet-100 text-violet-700">
                {length(@import_preview.preset_blocks)}
              </span>
            </h4>
            <%= if @import_preview.preset_blocks == [] do %>
              <p class="text-xs text-zinc-400 italic">No preset blocks in this file.</p>
            <% else %>
              <div class="space-y-1.5">
                <%= for entry <- @import_preview.preset_blocks do %>
                  <%
                    name = entry["name"] || entry[:name] || "(unnamed)"
                    blocks = entry["blocks"] || entry[:blocks] || []
                    group = entry["group"] || entry[:group]
                  %>
                  <div class="flex items-center justify-between gap-2 px-3 py-2 bg-zinc-50 border border-zinc-200 rounded-lg">
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-zinc-900 truncate">{name}</p>
                      <div class="flex items-center gap-1.5">
                        <span class="text-[10px] text-zinc-400">{length(blocks)} blocks</span>
                        <span :if={group} class="inline-flex items-center px-1.5 py-0.5 text-[10px] font-semibold rounded bg-amber-100 text-amber-700">
                          {group}
                        </span>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <p class="text-xs text-zinc-500">
            Items with names that already exist will be skipped during import.
          </p>
        </div>

        <%!-- Footer --%>
        <div class="px-5 py-3 border-t border-zinc-200 bg-white flex items-center justify-end gap-2 shrink-0">
          <button
            type="button"
            phx-click="cancel_import"
            class="px-4 py-2 text-sm font-medium text-zinc-700 bg-white border border-zinc-300 rounded-md hover:bg-zinc-50 transition-colors"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="confirm_import"
            class="px-4 py-2 text-sm font-medium text-white bg-green-600 rounded-md hover:bg-green-700 transition-colors shadow-sm"
          >
            Import {length(@import_preview.drafts) + length(@import_preview.preset_blocks)} item(s)
          </button>
        </div>
      </div>
    </div>

    <%!-- Preset Blocks Drawer --%>
    <div
      :if={@drawer_open}
      class="fixed inset-0 z-50 flex justify-end"
      phx-window-keydown="close_drawer"
      phx-key="Escape"
    >
      <%!-- Backdrop --%>
      <div class="absolute inset-0 bg-zinc-900/30" phx-click="close_drawer"></div>

      <%!-- Drawer panel --%>
      <div class="relative w-full max-w-md bg-white shadow-xl flex flex-col overflow-hidden">
        <%!-- Drawer header --%>
        <div class="px-4 py-3 border-b border-zinc-200 bg-zinc-50 flex items-center justify-between shrink-0">
          <div class="flex items-center gap-2">
            <%= if @drawer_mode != :list do %>
              <button
                type="button"
                phx-click="drawer_back"
                class="p-1 rounded text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 transition-colors"
                title="Back to list"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </button>
            <% end %>
            <h3 class="text-sm font-semibold text-zinc-800">
              <%= case @drawer_mode do %>
                <% :list -> %>Preset Blocks
                <% :new -> %>New Preset Block
                <% :edit -> %>Edit Preset Block
              <% end %>
            </h3>
            <span :if={@drawer_mode == :list} class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-violet-100 text-violet-700">
              {length(@preset_blocks)}
            </span>
          </div>
          <button
            type="button"
            phx-click="close_drawer"
            class="p-1.5 rounded text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 transition-colors"
            title="Close"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%!-- Drawer body --%>
        <div class="flex-1 overflow-y-auto">
          <%= if @drawer_mode == :list do %>
            <%!-- List mode --%>
            <div class="p-3">
              <button
                type="button"
                phx-click="drawer_new"
                class="w-full inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-violet-600 text-white hover:bg-violet-700 transition-colors shadow-sm mb-3"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
                New Preset Block
              </button>

              <%= if @preset_blocks == [] do %>
                <div class="text-center py-8">
                  <svg class="mx-auto w-8 h-8 text-zinc-300 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                  </svg>
                  <p class="text-sm text-zinc-400">No preset blocks yet.</p>
                  <p class="text-xs text-zinc-400 mt-0.5">Create reusable block snippets to insert into drafts.</p>
                </div>
              <% else %>
                <%
                  grouped = Enum.group_by(@preset_blocks, fn pb -> pb.group || "" end)
                  group_names = grouped |> Map.keys() |> Enum.filter(& &1 != "") |> Enum.sort()
                  ungrouped = Map.get(grouped, "", [])
                %>

                <div class="space-y-2">
                  <%!-- Grouped sections --%>
                  <%= for group_name <- group_names do %>
                    <% collapsed = MapSet.member?(@collapsed_groups, group_name) %>
                    <div class="border border-zinc-200 rounded-lg overflow-hidden">
                      <button
                        type="button"
                        phx-click="toggle_group_collapse"
                        phx-value-group={group_name}
                        class="w-full flex items-center gap-2 px-3 py-2 bg-zinc-100 hover:bg-zinc-200 transition-colors text-left"
                      >
                        <svg class={"w-3 h-3 text-zinc-500 transition-transform #{if !collapsed, do: "rotate-90"}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                        </svg>
                        <svg class="w-3.5 h-3.5 text-amber-500" fill="currentColor" viewBox="0 0 20 20">
                          <path d="M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z" />
                        </svg>
                        <span class="text-xs font-semibold text-zinc-700 flex-1 truncate">{group_name}</span>
                        <span class="text-[10px] text-zinc-400">{length(grouped[group_name])}</span>
                      </button>
                      <div :if={!collapsed} class="p-2 space-y-1.5">
                        <%= for pb <- grouped[group_name] do %>
                          {preset_block_card(Map.put(assigns, :pb, pb))}
                        <% end %>
                      </div>
                    </div>
                  <% end %>

                  <%!-- Ungrouped --%>
                  <%= if ungrouped != [] do %>
                    <%= if group_names != [] do %>
                      <div class="pt-1">
                        <p class="px-1 pb-1 text-[10px] font-semibold text-zinc-400 uppercase">Ungrouped</p>
                      </div>
                    <% end %>
                    <%= for pb <- ungrouped do %>
                      {preset_block_card(Map.put(assigns, :pb, pb))}
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% else %>
            <%!-- New / Edit mode --%>
            <div class="p-4 space-y-4">
              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-1.5">Name</label>
                <input
                  type="text"
                  value={@pb_name}
                  phx-keyup="update_pb_name"
                  placeholder="e.g. Timeframes, Comments Section"
                  class="w-full px-3 py-2 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-violet-500 focus:border-violet-500"
                />
              </div>

              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-1.5">
                  Group <span class="text-zinc-400 font-normal">(optional)</span>
                </label>
                <input
                  type="text"
                  value={@pb_group}
                  phx-keyup="update_pb_group"
                  placeholder="e.g. Timeframes, Analysis"
                  list="preset-block-groups"
                  class="w-full px-3 py-2 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-violet-500 focus:border-violet-500"
                />
                <datalist id="preset-block-groups">
                  <%= for g <- @preset_block_groups do %>
                    <option value={g} />
                  <% end %>
                </datalist>
              </div>

              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-1.5">
                  Blocks <span class="text-zinc-400 font-normal">({length(@pb_blocks)})</span>
                </label>

                <%= if @pb_blocks == [] do %>
                  <div class="text-center py-6 border-2 border-dashed border-zinc-200 rounded-lg">
                    <p class="text-sm text-zinc-400 mb-2">No blocks yet.</p>
                    <div class="flex items-center justify-center gap-2">
                      <button
                        type="button"
                        phx-click="pb_add_block"
                        phx-value-type="paragraph"
                        class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
                      >
                        + Paragraph
                      </button>
                      <button
                        type="button"
                        phx-click="pb_add_block"
                        phx-value-type="toggle"
                        class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-violet-50 text-violet-700 hover:bg-violet-100 transition-colors"
                      >
                        + Toggle
                      </button>
                    </div>
                  </div>
                <% else %>
                  <div class="space-y-1.5">
                    <%= for {block, idx} <- Enum.with_index(@pb_blocks) do %>
                      <div class={[
                        "flex items-start gap-1.5 p-2 rounded-lg border transition-colors",
                        if(block["type"] == "toggle",
                          do: "bg-violet-50/50 border-violet-200",
                          else: "bg-zinc-50 border-zinc-200"
                        )
                      ]}>
                        <div class="flex flex-col items-center gap-0.5 pt-1 shrink-0">
                          <span class="text-[10px] text-zinc-400 font-mono">{idx + 1}</span>
                          <button
                            type="button"
                            phx-click="pb_toggle_block_type"
                            phx-value-index={idx}
                            class={[
                              "px-1 py-0.5 text-[10px] font-semibold rounded cursor-pointer transition-colors",
                              if(block["type"] == "toggle",
                                do: "bg-violet-200 text-violet-700 hover:bg-violet-300",
                                else: "bg-zinc-200 text-zinc-600 hover:bg-zinc-300"
                              )
                            ]}
                          >
                            {if block["type"] == "toggle", do: "TGL", else: "TXT"}
                          </button>
                        </div>
                        <div class="flex-1 min-w-0">
                          <%= if block["type"] == "toggle" do %>
                            <input
                              type="text"
                              value={block["text"] || ""}
                              phx-keyup="pb_update_block_text"
                              phx-value-index={idx}
                              placeholder="Toggle title..."
                              class="w-full px-2 py-1 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-violet-500 focus:border-violet-500"
                            />
                          <% else %>
                            <textarea
                              phx-keyup="pb_update_block_text"
                              phx-value-index={idx}
                              placeholder="Paragraph text..."
                              rows="1"
                              class="w-full px-2 py-1 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-violet-500 focus:border-violet-500 resize-y"
                            ><%= block["text"] || "" %></textarea>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-0.5 shrink-0 pt-1">
                          <button
                            type="button"
                            phx-click="pb_move_block_up"
                            phx-value-index={idx}
                            disabled={idx == 0}
                            class="p-0.5 rounded text-zinc-400 hover:text-zinc-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                          >
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
                            </svg>
                          </button>
                          <button
                            type="button"
                            phx-click="pb_move_block_down"
                            phx-value-index={idx}
                            disabled={idx == length(@pb_blocks) - 1}
                            class="p-0.5 rounded text-zinc-400 hover:text-zinc-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                          >
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                            </svg>
                          </button>
                          <button
                            type="button"
                            phx-click="pb_delete_block"
                            phx-value-index={idx}
                            class="p-0.5 rounded text-zinc-400 hover:text-red-600 transition-colors"
                          >
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                            </svg>
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <div class="mt-2 flex items-center justify-center gap-2">
                    <button
                      type="button"
                      phx-click="pb_add_block"
                      phx-value-type="paragraph"
                      class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
                    >
                      + Paragraph
                    </button>
                    <button
                      type="button"
                      phx-click="pb_add_block"
                      phx-value-type="toggle"
                      class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-violet-50 text-violet-700 hover:bg-violet-100 transition-colors"
                    >
                      + Toggle
                    </button>
                  </div>
                <% end %>
              </div>

              <div class="pt-2 border-t border-zinc-100">
                <button
                  type="button"
                  phx-click="save_preset_block"
                  class="w-full inline-flex items-center justify-center gap-1.5 px-4 py-2 text-sm font-medium bg-violet-600 text-white rounded-md hover:bg-violet-700 transition-colors shadow-sm"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                  {if @editing_preset_block, do: "Update Preset Block", else: "Save Preset Block"}
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Preset block card component ──────────────────────────────────────

  defp preset_block_card(assigns) do
    ~H"""
    <div class="bg-zinc-50 border border-zinc-200 rounded-lg p-3">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium text-zinc-900 truncate">{@pb.name}</p>
          <div class="flex items-center gap-1.5 mt-1">
            <span class="inline-flex items-center px-1.5 py-0.5 text-[10px] font-semibold rounded bg-violet-100 text-violet-700">
              {length(@pb.blocks)} blocks
            </span>
            <span :if={@pb.group} class="inline-flex items-center px-1.5 py-0.5 text-[10px] font-semibold rounded bg-amber-100 text-amber-700">
              {@pb.group}
            </span>
            <span class="text-[10px] text-zinc-400">
              {Calendar.strftime(@pb.updated_at, "%b %d, %H:%M")}
            </span>
          </div>
          <%!-- Block preview --%>
          <div class="mt-2 space-y-0.5">
            <%= for block <- Enum.take(@pb.blocks, 3) do %>
              <div class="flex items-center gap-1 text-[10px] text-zinc-500">
                <span class={if(block["type"] == "toggle", do: "text-violet-500", else: "text-zinc-400")}>
                  {if block["type"] == "toggle", do: "▸", else: "¶"}
                </span>
                <span class="truncate">{block["text"] || "(empty)"}</span>
              </div>
            <% end %>
            <p :if={length(@pb.blocks) > 3} class="text-[10px] text-zinc-400 italic">
              +{length(@pb.blocks) - 3} more...
            </p>
          </div>
        </div>
        <div class="flex flex-col gap-1 shrink-0">
          <button
            type="button"
            phx-click="insert_preset_block"
            phx-value-id={@pb.id}
            class="px-2.5 py-1 text-xs font-medium rounded-md bg-green-100 text-green-700 hover:bg-green-200 transition-colors"
            title="Insert into draft"
          >
            Insert
          </button>
          <button
            type="button"
            phx-click="drawer_edit"
            phx-value-id={@pb.id}
            class="px-2.5 py-1 text-xs font-medium rounded-md bg-zinc-100 text-zinc-600 hover:bg-zinc-200 transition-colors"
          >
            Edit
          </button>
          <button
            type="button"
            phx-click="delete_preset_block"
            phx-value-id={@pb.id}
            class="px-2.5 py-1 text-xs font-medium rounded-md bg-red-50 text-red-600 hover:bg-red-100 transition-colors"
            data-confirm={"Delete preset block \"#{@pb.name}\"?"}
          >
            Delete
          </button>
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

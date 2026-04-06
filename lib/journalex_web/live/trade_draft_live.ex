defmodule JournalexWeb.TradeDraftLive do
  @moduledoc """
  LiveView page for managing combined (trade) drafts with inline editing.

  Two-column layout:
  - Left panel: combined draft list with bulk create, CRUD
  - Right panel: tabbed editor (Metadata | Writeup) for the selected combined draft
  """
  use JournalexWeb, :live_view

  alias Journalex.CombinedDrafts
  alias Journalex.MetadataDrafts
  alias Journalex.Notion
  alias Journalex.WriteupDrafts
  alias Journalex.Settings
  alias JournalexWeb.BlockHelpers

  @supported_versions [1, 2]

  # ── Mount ───────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    default_version = Settings.get_default_metadata_version()

    socket =
      socket
      # Combined draft list
      |> assign(:combined_drafts, CombinedDrafts.list_drafts())
      |> assign(:selected_cd_ids, MapSet.new())
      # Inline create/edit form
      |> assign(:cd_editing, nil)
      |> assign(:cd_name, "")
      # Bulk create
      |> assign(:bulk_mode, false)
      |> assign(:bulk_names, List.duplicate("", 2))
      |> assign(:bulk_auto_meta, true)
      |> assign(:bulk_auto_writeup, true)
      |> assign(:bulk_version, default_version)
      |> assign(:bulk_writeup_template_id, nil)
      # Editor state
      |> assign(:active_tab, :metadata)
      |> assign(:selected_draft, nil)
      # Metadata editor
      |> assign(:supported_versions, @supported_versions)
      |> assign(:form_version, default_version)
      |> assign(:draft_metadata, %{})
      # Writeup editor
      |> assign(:blocks, [])
      |> assign(:preset_blocks, WriteupDrafts.list_preset_blocks())
      |> assign(:preset_writeup_drafts, list_preset_writeup_drafts())
      |> assign(:active_block_index, nil)
      |> assign(:metadata_dirty, false)
      |> assign(:writeup_dirty, false)
      |> assign(:modified_draft_ids, MapSet.new())
      |> assign(:cd_delete_confirm, nil)

    {:ok, socket}
  end

  # ── Tab switching ───────────────────────────────────────────────────

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, tab)}
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
         |> assign(:writeup_dirty, true)
         |> put_toast(:info, "Applied \"#{draft.name}\" as template")}
    end
  end

  @impl true
  def handle_event("metadata_changed", _params, socket) do
    {:noreply, assign(socket, :metadata_dirty, true)}
  end

  # ── Combined draft selection ────────────────────────────────────────

  @impl true
  def handle_event("select_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = CombinedDrafts.get_draft!(id)

    md = draft.metadata_draft
    wd = draft.writeup_draft

    socket =
      socket
      |> assign(:selected_draft, draft)
      |> assign(:cd_editing, nil)
      |> assign(:cd_name, "")
      # Load metadata state
      |> assign(:form_version, if(md, do: md.metadata_version, else: Settings.get_default_metadata_version()))
      |> assign(:draft_metadata, if(md, do: md.metadata || %{}, else: %{}))
      # Load writeup state
      |> assign(:blocks, if(wd, do: wd.blocks || [], else: []))
      |> assign(:active_block_index, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_draft", _params, socket) do
    {:noreply, clear_editor(socket)}
  end

  # ── Combined draft CRUD ─────────────────────────────────────────────

  @impl true
  def handle_event("cd_update_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :cd_name, value)}
  end

  @impl true
  def handle_event("cd_save", _params, socket) do
    name = String.trim(socket.assigns.cd_name)

    if name == "" do
      {:noreply, put_toast(socket, :error, "Name cannot be empty")}
    else
      result =
        if socket.assigns.cd_editing do
          CombinedDrafts.update_draft(socket.assigns.cd_editing, %{name: name})
        else
          create_combined_draft_with_children(name, socket.assigns.form_version)
        end

      case result do
        {:ok, draft} ->
          action = if socket.assigns.cd_editing, do: "Updated", else: "Created"

          {:noreply,
           socket
           |> assign(:combined_drafts, CombinedDrafts.list_drafts())
           |> assign(:cd_editing, nil)
           |> assign(:cd_name, "")
           |> load_selected_draft(draft.id)
           |> put_toast(:info, "#{action} trade draft \"#{draft.name}\"")}

        {:error, changeset} ->
          msg = format_changeset_errors(changeset)
          {:noreply, put_toast(socket, :error, "Failed: #{msg}")}
      end
    end
  end

  @impl true
  def handle_event("cd_edit", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = CombinedDrafts.get_draft!(id)
    {:noreply, socket |> assign(:cd_editing, draft) |> assign(:cd_name, draft.name)}
  end

  @impl true
  def handle_event("cd_cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:cd_editing, nil) |> assign(:cd_name, "")}
  end

  @impl true
  def handle_event("cd_toggle_select", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    ids = socket.assigns.selected_cd_ids
    new_ids = if MapSet.member?(ids, id), do: MapSet.delete(ids, id), else: MapSet.put(ids, id)
    {:noreply, assign(socket, :selected_cd_ids, new_ids)}
  end

  @impl true
  def handle_event("cd_select_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.combined_drafts, & &1.id)
    {:noreply, assign(socket, :selected_cd_ids, all_ids)}
  end

  @impl true
  def handle_event("cd_deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_cd_ids, MapSet.new())}
  end

  @impl true
  def handle_event("cd_bulk_delete", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_cd_ids)
    count = length(ids)
    {:noreply, assign(socket, :cd_delete_confirm, %{pending_ids: ids, label: "#{count} selected draft(s)"})}
  end

  @impl true
  def handle_event("cd_delete_all", _params, socket) do
    all_ids = Enum.map(socket.assigns.combined_drafts, & &1.id)
    count = length(all_ids)
    {:noreply, assign(socket, :cd_delete_confirm, %{pending_ids: all_ids, label: "all #{count} draft(s)"})}
  end

  @impl true
  def handle_event("cd_delete", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = Enum.find(socket.assigns.combined_drafts, &(&1.id == id))
    name = if draft, do: draft.name, else: "draft"
    {:noreply, assign(socket, :cd_delete_confirm, %{pending_ids: [id], label: "\"#{name}\""})}
  end

  @impl true
  def handle_event("cd_confirm_delete", %{"mode" => mode_str}, socket) do
    %{pending_ids: ids, label: label} = socket.assigns.cd_delete_confirm

    mode =
      case mode_str do
        "deep" -> :deep
        _ -> :shallow
      end

    selected_id = socket.assigns.selected_draft && socket.assigns.selected_draft.id
    socket = assign(socket, :cd_delete_confirm, nil)

    case CombinedDrafts.delete_drafts(ids, mode: mode) do
      {:ok, count} when is_integer(count) ->
        socket =
          socket
          |> assign(:combined_drafts, CombinedDrafts.list_drafts())
          |> assign(:selected_cd_ids, MapSet.new())
          |> put_toast(:info, "Deleted #{label}")

        socket = if selected_id && selected_id in ids, do: clear_editor(socket), else: socket
        {:noreply, socket}

      {:ok, %{combined_count: total} = stats} ->
        parts =
          ["#{total} draft(s)"]
          |> then(&if stats.metadata_count > 0, do: &1 ++ ["#{stats.metadata_count} metadata draft(s)"], else: &1)
          |> then(&if stats.writeup_count > 0, do: &1 ++ ["#{stats.writeup_count} writeup draft(s)"], else: &1)
          |> Enum.join(", ")

        socket =
          socket
          |> assign(:combined_drafts, CombinedDrafts.list_drafts())
          |> assign(:selected_cd_ids, MapSet.new())
          |> put_toast(:info, "Deleted #{parts}")

        socket = if selected_id && selected_id in ids, do: clear_editor(socket), else: socket
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_toast(socket, :error, "Failed to delete #{label}")}
    end
  end

  @impl true
  def handle_event("cd_cancel_delete", _params, socket) do
    {:noreply, assign(socket, :cd_delete_confirm, nil)}
  end

  # ── Bulk create ─────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_bulk", _params, socket) do
    {:noreply,
     socket
     |> assign(:bulk_mode, !socket.assigns.bulk_mode)
     |> assign(:bulk_names, List.duplicate("", 2))
     |> assign(:bulk_auto_meta, true)
     |> assign(:bulk_auto_writeup, true)
     |> assign(:bulk_version, Settings.get_default_metadata_version())
     |> assign(:bulk_writeup_template_id, nil)}
  end

  @impl true
  def handle_event("bulk_toggle_auto_meta", _params, socket) do
    {:noreply, assign(socket, :bulk_auto_meta, !socket.assigns.bulk_auto_meta)}
  end

  @impl true
  def handle_event("bulk_toggle_auto_writeup", _params, socket) do
    {:noreply, assign(socket, :bulk_auto_writeup, !socket.assigns.bulk_auto_writeup)}
  end

  @impl true
  def handle_event("bulk_set_version", %{"value" => v}, socket) do
    {:noreply, assign(socket, :bulk_version, String.to_integer(v))}
  end

  @impl true
  def handle_event("bulk_set_writeup_template", %{"value" => v}, socket) do
    template_id = case v do
      "none" -> nil
      str -> String.to_integer(str)
    end
    {:noreply, assign(socket, :bulk_writeup_template_id, template_id)}
  end

  @impl true
  def handle_event("bulk_update_name", %{"value" => value, "index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    names = List.replace_at(socket.assigns.bulk_names, idx, value)
    {:noreply, assign(socket, :bulk_names, names)}
  end

  @impl true
  def handle_event("bulk_add_row", _params, socket) do
    {:noreply, assign(socket, :bulk_names, socket.assigns.bulk_names ++ [""])}
  end

  @impl true
  def handle_event("bulk_remove_row", _params, socket) do
    names = socket.assigns.bulk_names
    {:noreply, assign(socket, :bulk_names, Enum.take(names, max(length(names) - 1, 1)))}
  end

  @impl true
  def handle_event("bulk_create", _params, socket) do
    names =
      socket.assigns.bulk_names
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if names == [] do
      {:noreply, put_toast(socket, :error, "Please enter at least one name")}
    else
      auto_meta = socket.assigns.bulk_auto_meta
      auto_writeup = socket.assigns.bulk_auto_writeup
      version = socket.assigns.bulk_version
      template_id = socket.assigns.bulk_writeup_template_id

      # Fetch template blocks once before the loop
      template_blocks =
        if auto_writeup && template_id do
          case WriteupDrafts.get_draft(template_id) do
            nil -> []
            draft -> draft.blocks || []
          end
        else
          []
        end

      results =
        Enum.map(names, fn name ->
          # Create combined draft first to prevent orphaned children on failure
          case CombinedDrafts.create_draft(%{name: name}) do
            {:ok, cd} ->
              md_id =
                if auto_meta do
                  case MetadataDrafts.create_draft(%{name: name, metadata_version: version, metadata: %{}}) do
                    {:ok, md} -> md.id
                    {:error, _} -> nil
                  end
                end

              wd_id =
                if auto_writeup do
                  case WriteupDrafts.create_draft(%{name: name, blocks: template_blocks}) do
                    {:ok, wd} -> wd.id
                    {:error, _} -> nil
                  end
                end

              if md_id || wd_id do
                CombinedDrafts.update_draft(cd, %{metadata_draft_id: md_id, writeup_draft_id: wd_id})
              else
                {:ok, cd}
              end

            {:error, _} = err ->
              err
          end
        end)

      created = Enum.count(results, &match?({:ok, _}, &1))
      failed_names =
        names
        |> Enum.zip(results)
        |> Enum.filter(fn {_name, result} -> match?({:error, _}, result) end)
        |> Enum.map(fn {name, _} -> name end)

      parts =
        [if(auto_meta, do: "metadata V#{version}"), if(auto_writeup, do: "writeup")]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" + ")

      suffix = if parts != "", do: " with #{parts} drafts", else: ""

      socket =
        if failed_names == [] do
          socket
          |> assign(:combined_drafts, CombinedDrafts.list_drafts())
          |> assign(:bulk_mode, false)
          |> assign(:bulk_names, List.duplicate("", 2))
          |> put_toast(:info, "Created #{created} trade draft(s)#{suffix}")
        else
          socket
          |> assign(:combined_drafts, CombinedDrafts.list_drafts())
          |> put_toast(:error, "Created #{created}, failed: #{Enum.join(failed_names, ", ")}")
        end

      {:noreply, socket}
    end
  end

  # ── Metadata version switching ──────────────────────────────────────

  @impl true
  def handle_event("change_version", %{"version" => version_str}, socket) do
    {version, _} = Integer.parse(version_str)

    if version in @supported_versions do
      {:noreply, socket |> assign(:form_version, version) |> assign(:metadata_dirty, true)}
    else
      {:noreply, socket}
    end
  end

  # ── Save metadata ──────────────────────────────────────────────────

  @impl true
  def handle_event("save_metadata", params, socket) do
    selected = socket.assigns.selected_draft

    if is_nil(selected) do
      {:noreply, put_toast(socket, :error, "No trade draft selected")}
    else
      version = socket.assigns.form_version
      metadata = JournalexWeb.MetadataParamsBuilder.build(params, version)

      attrs = %{
        name: selected.name,
        metadata_version: version,
        metadata: metadata
      }

      md = selected.metadata_draft

      result =
        if md do
          MetadataDrafts.update_draft(md, attrs)
        else
          MetadataDrafts.create_draft(attrs)
        end

      case result do
        {:ok, saved_md} ->
          # Link to combined draft if newly created
          socket =
            if is_nil(md) do
              case CombinedDrafts.update_draft(selected, %{metadata_draft_id: saved_md.id}) do
                {:ok, _} -> socket
                {:error, _} -> put_toast(socket, :error, "Saved metadata but failed to link")
              end
            else
              socket
            end

          {:noreply,
           socket
           |> assign(:combined_drafts, CombinedDrafts.list_drafts())
           |> load_selected_draft(selected.id)
           |> update(:modified_draft_ids, &MapSet.put(&1, selected.id))
           |> put_toast(:info, "Metadata saved")}

        {:error, changeset} ->
          msg = format_changeset_errors(changeset)
          {:noreply, put_toast(socket, :error, "Failed to save metadata: #{msg}")}
      end
    end
  end

  # ── Save writeup ───────────────────────────────────────────────────

  @impl true
  def handle_event("save_writeup", _params, socket) do
    selected = socket.assigns.selected_draft

    if is_nil(selected) do
      {:noreply, put_toast(socket, :error, "No trade draft selected")}
    else
      blocks = socket.assigns.blocks
      wd = selected.writeup_draft

      result =
        if wd do
          WriteupDrafts.update_draft(wd, %{name: selected.name, blocks: blocks})
        else
          WriteupDrafts.create_draft(%{name: selected.name, blocks: blocks})
        end

      case result do
        {:ok, saved_wd} ->
          socket =
            if is_nil(wd) do
              case CombinedDrafts.update_draft(selected, %{writeup_draft_id: saved_wd.id}) do
                {:ok, _} -> socket
                {:error, _} -> put_toast(socket, :error, "Saved writeup but failed to link")
              end
            else
              socket
            end

          {:noreply,
           socket
           |> assign(:combined_drafts, CombinedDrafts.list_drafts())
           |> load_selected_draft(selected.id)
           |> update(:modified_draft_ids, &MapSet.put(&1, selected.id))
           |> put_toast(:info, "Writeup saved")}

        {:error, changeset} ->
          msg = format_changeset_errors(changeset)
          {:noreply, put_toast(socket, :error, "Failed to save writeup: #{msg}")}
      end
    end
  end

  # ── Notion placeholder ──────────────────────────────────────────────

  @impl true
  def handle_event("create_placeholder", _params, socket) do
    selected = socket.assigns.selected_draft

    cond do
      is_nil(selected) ->
        {:noreply, put_toast(socket, :error, "No trade draft selected")}

      not is_nil(selected.notion_page_id) ->
        {:noreply, put_toast(socket, :error, "Placeholder already exists — use Recreate to replace")}

      true ->
        blocks = CombinedDrafts.placeholder_blocks()
        version = socket.assigns.form_version

        case Notion.create_placeholder_page(selected.name, blocks, metadata_version: version) do
          {:ok, page} ->
            page_id = Map.get(page, "id")

            case CombinedDrafts.set_notion_page_id(selected, page_id) do
              {:ok, _} ->
                notion_url = notion_page_url(page_id)

                {:noreply,
                 socket
                 |> assign(:combined_drafts, CombinedDrafts.list_drafts())
                 |> load_selected_draft(selected.id)
                 |> put_toast(:info, "Placeholder created — #{notion_url}")}

              {:error, _} ->
                {:noreply, put_toast(socket, :error, "Page created but failed to save link")}
            end

          {:error, reason} ->
            {:noreply, put_toast(socket, :error, "Failed to create placeholder: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("recreate_placeholder", _params, socket) do
    selected = socket.assigns.selected_draft

    if is_nil(selected) do
      {:noreply, put_toast(socket, :error, "No trade draft selected")}
    else
      case CombinedDrafts.clear_notion_page_id(selected) do
        {:ok, _} ->
          blocks = CombinedDrafts.placeholder_blocks()
          version = socket.assigns.form_version

          case Notion.create_placeholder_page(selected.name, blocks, metadata_version: version) do
            {:ok, page} ->
              page_id = Map.get(page, "id")

              case CombinedDrafts.set_notion_page_id(selected, page_id) do
                {:ok, _} ->
                  notion_url = notion_page_url(page_id)

                  {:noreply,
                   socket
                   |> assign(:combined_drafts, CombinedDrafts.list_drafts())
                   |> load_selected_draft(selected.id)
                   |> put_toast(:info, "Placeholder recreated — old one orphaned — #{notion_url}")}

                {:error, _} ->
                  {:noreply, put_toast(socket, :error, "Page created but failed to save link")}
              end

            {:error, reason} ->
              {:noreply, put_toast(socket, :error, "Failed to recreate placeholder: #{inspect(reason)}")}
          end

        {:error, _} ->
          {:noreply, put_toast(socket, :error, "Failed to clear old placeholder link")}
      end
    end
  end

  # ── Block editor events ─────────────────────────────────────────────

  @impl true
  def handle_event("add_block", %{"type" => type, "after" => after_str}, socket) do
    {after_idx, _} = Integer.parse(after_str)
    blocks = BlockHelpers.add_after(socket.assigns.blocks, type, after_idx)
    {:noreply, socket |> assign(:blocks, blocks) |> assign(:active_block_index, after_idx + 1) |> assign(:writeup_dirty, true)}
  end

  @impl true
  def handle_event("add_block_end", %{"type" => type}, socket) do
    blocks = BlockHelpers.add_end(socket.assigns.blocks, type)
    {:noreply, socket |> assign(:blocks, blocks) |> assign(:active_block_index, length(blocks) - 1) |> assign(:writeup_dirty, true)}
  end

  @impl true
  def handle_event("delete_block", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {:noreply, socket |> assign(:blocks, BlockHelpers.delete(socket.assigns.blocks, idx)) |> assign(:writeup_dirty, true)}
  end

  @impl true
  def handle_event("move_block_up", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {:noreply, socket |> assign(:blocks, BlockHelpers.move_up(socket.assigns.blocks, idx)) |> assign(:writeup_dirty, true)}
  end

  @impl true
  def handle_event("move_block_down", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {:noreply, socket |> assign(:blocks, BlockHelpers.move_down(socket.assigns.blocks, idx)) |> assign(:writeup_dirty, true)}
  end

  @impl true
  def handle_event("update_block_text", %{"index" => idx_str, "value" => value}, socket) do
    {idx, _} = Integer.parse(idx_str)
    blocks = BlockHelpers.update_text(socket.assigns.blocks, idx, value)
    {:noreply, socket |> assign(:blocks, blocks) |> assign(:active_block_index, idx) |> assign(:writeup_dirty, true)}
  end

  @impl true
  def handle_event("toggle_block_type", %{"index" => idx_str}, socket) do
    {idx, _} = Integer.parse(idx_str)
    {:noreply, socket |> assign(:blocks, BlockHelpers.toggle_type(socket.assigns.blocks, idx)) |> assign(:writeup_dirty, true)}
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
     |> assign(:writeup_dirty, true)
     |> put_toast(:info, "Inserted #{length(pb.blocks || [])} block(s) from \"#{pb.name}\"")}
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp clear_editor(socket) do
    socket
    |> assign(:selected_draft, nil)
    |> assign(:cd_editing, nil)
    |> assign(:cd_name, "")
    |> assign(:form_version, Settings.get_default_metadata_version())
    |> assign(:draft_metadata, %{})
    |> assign(:blocks, [])
    |> assign(:active_block_index, nil)
    |> assign(:metadata_dirty, false)
    |> assign(:writeup_dirty, false)
  end

  defp load_selected_draft(socket, draft_id) do
    draft = CombinedDrafts.get_draft!(draft_id)
    md = draft.metadata_draft
    wd = draft.writeup_draft

    socket
    |> assign(:selected_draft, draft)
    |> assign(:form_version, if(md, do: md.metadata_version, else: Settings.get_default_metadata_version()))
    |> assign(:draft_metadata, if(md, do: md.metadata || %{}, else: %{}))
    |> assign(:blocks, if(wd, do: wd.blocks || [], else: []))
    |> assign(:active_block_index, nil)
    |> assign(:metadata_dirty, false)
    |> assign(:writeup_dirty, false)
  end

  defp create_combined_draft_with_children(name, version) do
    md_result = MetadataDrafts.create_draft(%{name: name, metadata_version: version, metadata: %{}})
    wd_result = WriteupDrafts.create_draft(%{name: name, blocks: []})

    md_id = case md_result do
      {:ok, md} -> md.id
      _ -> nil
    end

    wd_id = case wd_result do
      {:ok, wd} -> wd.id
      _ -> nil
    end

    CombinedDrafts.create_draft(%{
      name: name,
      metadata_draft_id: md_id,
      writeup_draft_id: wd_id
    })
  end

  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp notion_page_url(page_id) when is_binary(page_id) do
    "https://notion.so/" <> String.replace(page_id, "-", "")
  end

  defp list_preset_writeup_drafts do
    WriteupDrafts.ensure_preset_draft()
    WriteupDrafts.list_preset_drafts()
  end

  # ── Render ──────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-lg font-bold text-zinc-900">Trade Drafts</h1>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <%!-- ═══════ Left panel: Draft list ═══════ --%>
        <div class="lg:col-span-4">
          <div class="bg-white rounded-lg border border-sky-200 shadow-sm overflow-hidden">
            <div class="px-5 py-3 bg-sky-50 border-b border-sky-100 flex items-center justify-between">
              <div>
                <h2 class="text-sm font-semibold text-sky-800 uppercase tracking-wide">Trade Drafts</h2>
                <p class="text-xs text-sky-600 mt-0.5">Combined metadata + writeup templates.</p>
              </div>
              <div class="flex items-center gap-2">
                <button
                  :if={!@bulk_mode && @combined_drafts != []}
                  phx-click="cd_delete_all"
                  class="text-xs px-2 py-1 rounded-md border border-red-200 bg-red-50 text-red-600 hover:bg-red-100 font-medium transition-colors"
                >
                  Delete all
                </button>
                <button
                  :if={!@bulk_mode}
                  phx-click="toggle_bulk"
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
            <div :if={@bulk_mode} class="px-5 py-4 border-b border-sky-100 bg-sky-50/50">
              <div class="flex items-center justify-between mb-3">
                <h4 class="text-xs font-semibold text-sky-700">Bulk Create</h4>
                <button phx-click="toggle_bulk" class="text-xs text-sky-600 hover:text-sky-800">Cancel</button>
              </div>
              <%!-- Auto-create options: two-row layout --%>
              <div class="mb-3 bg-white rounded-md border border-sky-200 overflow-hidden">
                <%!-- Metadata row --%>
                <div class="flex flex-wrap items-center gap-3 px-3 py-2 bg-amber-50/40 border-b border-sky-100">
                  <button
                    type="button"
                    phx-click="bulk_toggle_auto_meta"
                    class={[
                      "relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors",
                      if(@bulk_auto_meta, do: "bg-amber-500", else: "bg-zinc-300")
                    ]}
                  >
                    <span class={[
                      "pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform",
                      if(@bulk_auto_meta, do: "translate-x-4", else: "translate-x-0")
                    ]} />
                  </button>
                  <span class="text-xs font-medium text-amber-700">Metadata Draft</span>
                  <div :if={@bulk_auto_meta} class="inline-flex items-center gap-1.5">
                    <span class="text-[10px] text-amber-600 font-medium">Version:</span>
                    <select
                      phx-change="bulk_set_version"
                      class="px-1.5 py-0.5 text-xs border border-amber-200 rounded focus:outline-none focus:ring-1 focus:ring-amber-400"
                    >
                      <option value="1" selected={@bulk_version == 1}>V1</option>
                      <option value="2" selected={@bulk_version == 2}>V2</option>
                    </select>
                  </div>
                </div>
                <%!-- Writeup row --%>
                <div class="flex flex-wrap items-center gap-3 px-3 py-2">
                  <button
                    type="button"
                    phx-click="bulk_toggle_auto_writeup"
                    class={[
                      "relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors",
                      if(@bulk_auto_writeup, do: "bg-violet-500", else: "bg-zinc-300")
                    ]}
                  >
                    <span class={[
                      "pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform",
                      if(@bulk_auto_writeup, do: "translate-x-4", else: "translate-x-0")
                    ]} />
                  </button>
                  <span class="text-xs font-medium text-violet-700">Writeup Draft</span>
                  <div :if={@bulk_auto_writeup} class="inline-flex items-center gap-1.5">
                    <span class="text-[10px] text-violet-600 font-medium">Template:</span>
                    <select
                      phx-change="bulk_set_writeup_template"
                      class="px-1.5 py-0.5 text-xs border border-violet-200 rounded focus:outline-none focus:ring-1 focus:ring-violet-400"
                    >
                      <option value="none" selected={is_nil(@bulk_writeup_template_id)}>None (empty)</option>
                      <%= for draft <- @preset_writeup_drafts do %>
                        <option value={draft.id} selected={@bulk_writeup_template_id == draft.id}>
                          {draft.name} ({length(draft.blocks || [])} blocks)
                        </option>
                      <% end %>
                    </select>
                  </div>
                </div>
              </div>
              <div class="space-y-2">
                <%= for {name, i} <- Enum.with_index(@bulk_names) do %>
                  <div class="flex items-center gap-2">
                    <span class="text-[10px] text-sky-500 font-mono w-4 text-right shrink-0">{i + 1}</span>
                    <input
                      type="text"
                      value={name}
                      phx-keyup="bulk_update_name"
                      phx-value-index={i}
                      placeholder="Draft name..."
                      class="flex-1 px-2 py-1.5 text-sm border border-sky-200 rounded-md focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-sky-500"
                    />
                  </div>
                <% end %>
              </div>
              <div class="flex items-center justify-between mt-3">
                <div class="flex items-center gap-2">
                  <button
                    phx-click="bulk_add_row"
                    class="text-xs px-2 py-1 rounded border border-sky-200 text-sky-600 hover:bg-sky-100"
                  >
                    + Row
                  </button>
                  <button
                    :if={length(@bulk_names) > 1}
                    phx-click="bulk_remove_row"
                    class="text-xs px-2 py-1 rounded border border-sky-200 text-sky-600 hover:bg-sky-100"
                  >
                    − Row
                  </button>
                </div>
                <button
                  phx-click="bulk_create"
                  class="px-3 py-1.5 text-xs font-medium bg-sky-600 text-white rounded-md hover:bg-sky-700 transition-colors shadow-sm"
                >
                  Create {length(@bulk_names)} draft(s)
                </button>
              </div>
            </div>

            <%!-- Inline create form --%>
            <div :if={!@bulk_mode} class="px-5 py-4 border-b border-sky-100">
              <div class="flex items-center gap-2 mb-2">
                <h4 class="text-xs font-semibold text-sky-700">
                  {if @cd_editing, do: "Rename Draft", else: "New Trade Draft"}
                </h4>
                <button :if={@cd_editing} phx-click="cd_cancel_edit" class="text-xs text-sky-600 hover:text-sky-800">Cancel</button>
              </div>
              <div class="flex items-center gap-2">
                <input
                  type="text"
                  value={@cd_name}
                  phx-keyup="cd_update_name"
                  placeholder="Trade draft name..."
                  class="flex-1 px-2 py-1.5 text-sm border border-sky-200 rounded-md focus:outline-none focus:ring-2 focus:ring-sky-500 focus:border-sky-500"
                />
                <button
                  phx-click="cd_save"
                  class="px-4 py-1.5 text-xs font-medium bg-sky-600 text-white rounded-md hover:bg-sky-700 transition-colors shadow-sm"
                >
                  {if @cd_editing, do: "Update", else: "Create"}
                </button>
              </div>
            </div>

            <%!-- Draft list --%>
            <div :if={@combined_drafts == []} class="px-5 py-6 text-center text-sm text-sky-400">
              No trade drafts yet. Create one above.
            </div>
            <div :if={@combined_drafts != [] && MapSet.size(@selected_cd_ids) > 0} class="px-5 py-2 bg-red-50 border-b border-red-100 flex items-center justify-between gap-2">
              <span class="text-xs text-red-700 font-medium">{MapSet.size(@selected_cd_ids)} selected</span>
              <div class="flex items-center gap-2">
                <button phx-click="cd_deselect_all" class="text-xs text-zinc-500 hover:text-zinc-700">Deselect all</button>
                <button
                  phx-click="cd_bulk_delete"
                  class="text-xs px-2.5 py-1 rounded-md bg-red-600 text-white hover:bg-red-700 font-medium transition-colors"
                >
                  Delete selected
                </button>
              </div>
            </div>
            <ul :if={@combined_drafts != []} class="divide-y divide-sky-100">
              <%= for cd <- @combined_drafts do %>
                <li
                  class={[
                    "px-5 py-3 flex items-center justify-between gap-3 transition-colors",
                    if(@selected_draft && @selected_draft.id == cd.id,
                      do: "bg-sky-100 border-l-4 border-sky-500",
                      else: "hover:bg-sky-50/50"
                    )
                  ]}
                >
                  <input
                    type="checkbox"
                    checked={MapSet.member?(@selected_cd_ids, cd.id)}
                    phx-click="cd_toggle_select"
                    phx-value-id={cd.id}
                    class="w-4 h-4 shrink-0 rounded border-zinc-300 text-red-600 cursor-pointer"
                  />
                  <div
                    class="min-w-0 flex-1 cursor-pointer"
                    phx-click="select_draft"
                    phx-value-id={cd.id}
                  >
                    <p class="text-sm font-medium text-zinc-900 truncate">{cd.name}</p>
                    <div class="flex items-center gap-2 mt-0.5">
                      <span :if={cd.metadata_draft} class="inline-flex items-center gap-1 text-[10px] font-medium text-amber-700 bg-amber-50 px-1.5 py-0.5 rounded">
                        <span class="w-1.5 h-1.5 rounded-full bg-amber-400"></span>
                        V{cd.metadata_draft.metadata_version}
                      </span>
                      <span :if={is_nil(cd.metadata_draft)} class="text-[10px] text-zinc-400 italic">no metadata</span>
                      <span :if={cd.writeup_draft} class="inline-flex items-center gap-1 text-[10px] font-medium text-violet-700 bg-violet-50 px-1.5 py-0.5 rounded">
                        <span class="w-1.5 h-1.5 rounded-full bg-violet-400"></span>
                        {length(cd.writeup_draft.blocks || [])} blk
                      </span>
                      <span :if={is_nil(cd.writeup_draft)} class="text-[10px] text-zinc-400 italic">no writeup</span>
                      <span
                        :if={cd.applied_at}
                        class="inline-flex items-center gap-0.5 text-[10px] font-medium text-green-700 bg-green-50 px-1.5 py-0.5 rounded"
                        title={"Applied #{Calendar.strftime(cd.applied_at, "%Y-%m-%d %H:%M")}"}
                      >
                        <svg class="w-2.5 h-2.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                        </svg>
                        N
                      </span>
                      <span
                        :if={cd.notion_page_id && is_nil(cd.applied_at)}
                        class="inline-flex items-center gap-0.5 text-[10px] font-semibold text-blue-700 bg-blue-50 px-1.5 py-0.5 rounded"
                        title="Notion placeholder created"
                      >
                        N
                      </span>
                      <svg
                        :if={MapSet.member?(@modified_draft_ids, cd.id) || (@selected_draft && @selected_draft.id == cd.id && (@metadata_dirty || @writeup_dirty))}
                        class="w-3 h-3 shrink-0 text-orange-400"
                        fill="currentColor"
                        viewBox="0 0 24 24"
                        title="Unsaved changes"
                      >
                        <path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 000-1.41l-2.34-2.34a1 1 0 00-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/>
                      </svg>
                    </div>
                  </div>
                  <div class="flex items-center gap-1 shrink-0">
                    <button
                      phx-click="cd_edit"
                      phx-value-id={cd.id}
                      class="p-1.5 rounded text-zinc-400 hover:text-sky-600 hover:bg-sky-50 transition-colors"
                      title="Rename"
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
        </div>

        <%!-- ═══════ Right panel: Tabbed editor ═══════ --%>
        <div class="lg:col-span-8">
          <%= if @selected_draft do %>
            <div class="bg-white rounded-lg border border-zinc-200 shadow-sm overflow-hidden">
              <%!-- Header --%>
              <div class="px-5 py-3 bg-zinc-50 border-b border-zinc-200 flex items-center justify-between">
                <div>
                  <h2 class="text-sm font-semibold text-zinc-800">{@selected_draft.name}</h2>
                  <p class="text-xs text-zinc-500 mt-0.5">Edit metadata and writeup for this trade draft.</p>
                </div>
                <div class="flex items-center gap-2">
                  <%!-- Notion placeholder status --%>
                  <%= cond do %>
                    <% @selected_draft.applied_at != nil -> %>
                      <span class="inline-flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold bg-green-100 text-green-700 border border-green-200">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                        </svg>
                        Applied {Calendar.strftime(@selected_draft.applied_at, "%Y-%m-%d %H:%M")}
                      </span>
                    <% @selected_draft.notion_page_id != nil -> %>
                      <a
                        href={"https://notion.so/" <> String.replace(@selected_draft.notion_page_id, "-", "")}
                        target="_blank"
                        class="inline-flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-semibold bg-blue-100 text-blue-700 border border-blue-200 hover:bg-blue-200 transition-colors"
                        title="Open placeholder in Notion"
                      >
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                        </svg>
                        Placeholder
                      </a>
                      <button
                        phx-click="recreate_placeholder"
                        class="text-[10px] px-2 py-1 rounded-md border border-amber-200 bg-amber-50 text-amber-700 hover:bg-amber-100 font-medium transition-colors"
                        data-confirm="This will create a new placeholder and orphan the old one. Continue?"
                      >
                        Recreate
                      </button>
                    <% true -> %>
                      <button
                        phx-click="create_placeholder"
                        class="inline-flex items-center gap-1 text-[10px] px-2.5 py-1 rounded-md bg-blue-600 text-white hover:bg-blue-700 font-medium transition-colors shadow-sm"
                      >
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                        </svg>
                        Create Placeholder
                      </button>
                  <% end %>
                  <button
                    phx-click="deselect_draft"
                    class="text-xs text-zinc-500 hover:text-zinc-700 transition-colors"
                  >
                    Close
                  </button>
                </div>
              </div>

              <%!-- Tabs --%>
              <div class="flex border-b border-zinc-200">
                <button
                  phx-click="switch_tab"
                  phx-value-tab="metadata"
                  class={[
                    "flex-1 px-4 py-2.5 text-sm font-medium transition-colors text-center",
                    if(@active_tab == :metadata,
                      do: "text-amber-700 border-b-2 border-amber-500 bg-amber-50/50",
                      else: "text-zinc-500 hover:text-zinc-700 hover:bg-zinc-50"
                    )
                  ]}
                >
                  <span class="inline-flex items-center gap-1 justify-center">
                    Metadata
                    <span :if={@selected_draft.metadata_draft} class="text-[10px] text-amber-600">
                      (V{@selected_draft.metadata_draft.metadata_version})
                    </span>
                    <span :if={@metadata_dirty} class="w-2 h-2 rounded-full bg-amber-500 shrink-0" title="Unsaved changes"></span>
                  </span>
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="writeup"
                  class={[
                    "flex-1 px-4 py-2.5 text-sm font-medium transition-colors text-center",
                    if(@active_tab == :writeup,
                      do: "text-violet-700 border-b-2 border-violet-500 bg-violet-50/50",
                      else: "text-zinc-500 hover:text-zinc-700 hover:bg-zinc-50"
                    )
                  ]}
                >
                  <span class="inline-flex items-center gap-1 justify-center">
                    Writeup
                    <span :if={@selected_draft.writeup_draft} class="text-[10px] text-violet-600">
                      ({length(@selected_draft.writeup_draft.blocks || [])} blk)
                    </span>
                    <span :if={@writeup_dirty} class="w-2 h-2 rounded-full bg-violet-500 shrink-0" title="Unsaved changes"></span>
                  </span>
                </button>
              </div>

              <%!-- Tab content --%>
              <div class="p-5">
                <%!-- Metadata tab --%>
                <div :if={@active_tab == :metadata}>
                  <%!-- Version selector --%>
                  <div class="flex items-center gap-2 mb-4">
                    <span class="text-xs font-medium text-zinc-600">Version:</span>
                    <%= for version <- @supported_versions do %>
                      <button
                        type="button"
                        phx-click="change_version"
                        phx-value-version={version}
                        class={[
                          "px-3 py-1 text-xs font-medium rounded-full transition-colors",
                          if(@form_version == version,
                            do: "bg-amber-500 text-white",
                            else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                          )
                        ]}
                      >
                        V{version}
                      </button>
                    <% end %>
                  </div>

                  <% synthetic_item = %{
                    metadata: @draft_metadata,
                    metadata_version: @form_version,
                    result: nil,
                    realized_pl: nil,
                    action_chain: nil,
                    datetime: nil,
                    ticker: nil
                  } %>

                  <%= case @form_version do %>
                    <% 1 -> %>
                      <JournalexWeb.MetadataForm.v1
                        item={synthetic_item}
                        idx={0}
                        on_save_event="save_metadata"
                        on_change_event="metadata_changed"
                        save_label="Save Metadata"
                      />
                    <% 2 -> %>
                      <JournalexWeb.MetadataForm.v2
                        item={synthetic_item}
                        idx={0}
                        on_save_event="save_metadata"
                        on_change_event="metadata_changed"
                        save_label="Save Metadata"
                      />
                    <% _ -> %>
                      <div class="text-center text-sm text-zinc-500 py-4">
                        Unsupported version: {@form_version}
                      </div>
                  <% end %>
                </div>

                <%!-- Writeup tab --%>
                <div :if={@active_tab == :writeup}>
                  <div class="flex items-center justify-between mb-3">
                    <label class="block text-sm font-medium text-zinc-700">
                      Blocks <span class="text-zinc-400 font-normal">({length(@blocks)})</span>
                    </label>
                    <div :if={@preset_writeup_drafts != []} class="flex items-center gap-1.5 flex-wrap justify-end">
                      <span class="text-xs text-zinc-500">Template:</span>
                      <%= for draft <- @preset_writeup_drafts do %>
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

                  <JournalexWeb.BlockEditor.block_editor blocks={@blocks} preset_blocks={@preset_blocks} />

                  <div class="mt-4 flex justify-end">
                    <button
                      phx-click="save_writeup"
                      class="px-4 py-2 text-sm font-medium bg-violet-600 text-white rounded-md hover:bg-violet-700 transition-colors shadow-sm"
                    >
                      Save Writeup
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div class="bg-white rounded-lg border border-zinc-200 shadow-sm p-12 text-center">
              <p class="text-sm text-zinc-400">Select a trade draft from the list to edit its metadata and writeup.</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <%!-- ─── Delete confirmation modal ─── --%>
    <div
      :if={@cd_delete_confirm}
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-window-keydown="cd_cancel_delete"
      phx-key="Escape"
    >
      <div class="bg-white rounded-lg shadow-xl border border-zinc-200 w-full max-w-md mx-4 p-6">
        <h3 class="text-base font-semibold text-zinc-900 mb-1">Delete trade draft(s)</h3>
        <p class="text-sm text-zinc-500 mb-5">
          Also remove the associated metadata and writeup drafts for {@cd_delete_confirm.label}?
          Sub-drafts shared by other combined drafts will not be affected.
        </p>
        <div class="flex flex-col gap-2">
          <button
            phx-click="cd_confirm_delete"
            phx-value-mode="deep"
            class="w-full px-4 py-2.5 text-sm font-medium bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors"
          >
            Delete draft + sub-drafts
          </button>
          <button
            phx-click="cd_confirm_delete"
            phx-value-mode="shallow"
            class="w-full px-4 py-2.5 text-sm font-medium bg-zinc-600 text-white rounded-md hover:bg-zinc-700 transition-colors"
          >
            Delete draft only
          </button>
          <button
            phx-click="cd_cancel_delete"
            class="w-full px-4 py-2.5 text-sm font-medium text-zinc-500 hover:text-zinc-700 hover:bg-zinc-50 rounded-md transition-colors border border-zinc-200"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end
end

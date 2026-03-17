defmodule Journalex.WriteupDrafts do
  @moduledoc """
  Context for managing named writeup draft templates and reusable preset blocks.
  """
  import Ecto.Query, warn: false
  alias Journalex.Repo
  alias Journalex.WriteupDrafts.Draft
  alias Journalex.WriteupDrafts.PresetBlock

  @doc """
  List all writeup drafts, ordered by creation time ascending (oldest first).
  """
  def list_drafts do
    from(d in Draft, order_by: [asc: d.inserted_at])
    |> Repo.all()
  end

  @doc """
  List only preset-flagged writeup drafts, ordered by creation time ascending.
  """
  def list_preset_drafts do
    from(d in Draft, where: d.is_preset == true, order_by: [asc: d.inserted_at])
    |> Repo.all()
  end

  @doc """
  Get a single writeup draft by id. Raises if not found.
  """
  def get_draft!(id), do: Repo.get!(Draft, id)

  @doc """
  Get a single writeup draft by id. Returns nil if not found.
  """
  def get_draft(id), do: Repo.get(Draft, id)

  @doc """
  Create a new writeup draft.
  """
  def create_draft(attrs) do
    %Draft{}
    |> Draft.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing writeup draft.
  """
  def update_draft(%Draft{} = draft, attrs) do
    draft
    |> Draft.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Toggle the `is_preset` flag on a draft. Multiple drafts can be flagged
  as preset simultaneously — the flag is purely additive.
  Returns `{:ok, draft}` or `{:error, changeset}`.
  """
  def toggle_preset_draft(%Draft{is_preset: already_preset} = draft) do
    update_draft(draft, %{is_preset: !already_preset})
  end

  @doc """
  Delete a writeup draft. Returns `{:error, :preset}` for preset drafts.
  """
  def delete_draft(%Draft{is_preset: true}), do: {:error, :preset}

  def delete_draft(%Draft{} = draft) do
    Repo.delete(draft)
  end

  @preset_name "Standard Trade"
  @preset_blocks [
    %{"type" => "toggle", "text" => "1min", "children" => []},
    %{"type" => "toggle", "text" => "2min", "children" => []},
    %{"type" => "toggle", "text" => "5min", "children" => []},
    %{"type" => "toggle", "text" => "15min", "children" => []},
    %{"type" => "toggle", "text" => "daily", "children" => []},
    %{"type" => "paragraph", "text" => ""},
    %{"type" => "paragraph", "text" => "Environment Overview:"},
    %{"type" => "paragraph", "text" => ""},
    %{"type" => "paragraph", "text" => "Comments:"},
    %{"type" => "paragraph", "text" => "idea:"},
    %{"type" => "paragraph", "text" => ""},
    %{"type" => "paragraph", "text" => "What's good:"},
    %{"type" => "paragraph", "text" => ""},
    %{"type" => "paragraph", "text" => "What to improve:"},
    %{"type" => "paragraph", "text" => ""},
  ]

  @doc """
  Ensures a preset draft exists in the DB, creating it if absent.
  Called on LiveView mount so the preset is always present in the list.
  """
  def ensure_preset_draft do
    query = from(d in Draft, where: d.is_preset == true)

    if Repo.exists?(query) do
      :ok
    else
      %Draft{}
      |> Draft.changeset(%{name: @preset_name, blocks: @preset_blocks, is_preset: true})
      |> Repo.insert(on_conflict: :nothing)

      :ok
    end
  end

  # ── Preset blocks ───────────────────────────────────────────────────

  @doc """
  List all preset blocks, ordered by group (nulls last) then creation time ascending.
  """
  def list_preset_blocks do
    from(pb in PresetBlock, order_by: [asc_nulls_last: pb.group, asc: pb.inserted_at])
    |> Repo.all()
  end

  @doc """
  Return a sorted list of distinct non-nil group names.
  """
  def list_preset_block_groups do
    from(pb in PresetBlock,
      where: not is_nil(pb.group) and pb.group != "",
      distinct: true,
      select: pb.group,
      order_by: [asc: pb.group]
    )
    |> Repo.all()
  end

  @doc """
  Get a single preset block by id. Raises if not found.
  """
  def get_preset_block!(id), do: Repo.get!(PresetBlock, id)

  @doc """
  Create a new preset block.
  """
  def create_preset_block(attrs) do
    %PresetBlock{}
    |> PresetBlock.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing preset block.
  """
  def update_preset_block(%PresetBlock{} = preset_block, attrs) do
    preset_block
    |> PresetBlock.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a preset block.
  """
  def delete_preset_block(%PresetBlock{} = preset_block) do
    Repo.delete(preset_block)
  end

  @doc """
  Import preset blocks from a list of maps. Skips entries whose name already
  exists. Returns `{:ok, %{imported: count, skipped: count}}`.
  """
  def import_preset_blocks(entries) when is_list(entries) do
    existing_names =
      from(pb in PresetBlock, select: pb.name)
      |> Repo.all()
      |> MapSet.new()

    {imported, skipped} =
      Enum.reduce(entries, {0, 0}, fn entry, {imp, skip} ->
        name = Map.get(entry, "name") || Map.get(entry, :name)

        if name && !MapSet.member?(existing_names, name) do
          attrs = %{
            name: name,
            blocks: Map.get(entry, "blocks") || Map.get(entry, :blocks) || [],
            group: Map.get(entry, "group") || Map.get(entry, :group)
          }

          case create_preset_block(attrs) do
            {:ok, _} -> {imp + 1, skip}
            {:error, _} -> {imp, skip + 1}
          end
        else
          {imp, skip + 1}
        end
      end)

    {:ok, %{imported: imported, skipped: skipped}}
  end

  @doc """
  Import preset drafts from a list of maps. Skips entries whose name already
  exists. Preserves the `is_preset` flag from the serialised data.
  Returns `{:ok, %{imported: count, skipped: count}}`.
  """
  def import_drafts(entries) when is_list(entries) do
    existing_names =
      from(d in Draft, select: d.name)
      |> Repo.all()
      |> MapSet.new()

    {imported, skipped} =
      Enum.reduce(entries, {0, 0}, fn entry, {imp, skip} ->
        name = Map.get(entry, "name") || Map.get(entry, :name)

        if name && !MapSet.member?(existing_names, name) do
          attrs = %{
            name: name,
            blocks: Map.get(entry, "blocks") || Map.get(entry, :blocks) || [],
            is_preset: Map.get(entry, "is_preset") || Map.get(entry, :is_preset) || false
          }

          case create_draft(attrs) do
            {:ok, _} -> {imp + 1, skip}
            {:error, _} -> {imp, skip + 1}
          end
        else
          {imp, skip + 1}
        end
      end)

    {:ok, %{imported: imported, skipped: skipped}}
  end

  @doc """
  Export all preset drafts and preset blocks as a map.
  """
  def export_all do
    drafts =
      list_drafts()
      |> Enum.filter(& &1.is_preset)
      |> Enum.map(fn d -> %{name: d.name, blocks: d.blocks, is_preset: true} end)

    preset_blocks =
      list_preset_blocks()
      |> Enum.map(fn pb -> %{name: pb.name, group: pb.group, blocks: pb.blocks} end)

    %{drafts: drafts, preset_blocks: preset_blocks}
  end
end

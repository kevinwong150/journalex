defmodule Journalex.CombinedDrafts do
  @moduledoc """
  Context for managing combined draft templates that pair metadata + writeup drafts.
  """
  @behaviour Journalex.CombinedDraftsBehaviour

  import Ecto.Query, warn: false
  alias Journalex.Repo
  alias Journalex.CombinedDrafts.Draft
  alias Journalex.MetadataDrafts
  alias Journalex.WriteupDrafts

  @placeholder_blocks [
    %{"type" => "toggle", "text" => "1min:", "children" => []},
    %{"type" => "toggle", "text" => "2min:", "children" => []},
    %{"type" => "toggle", "text" => "5min:", "children" => []},
    %{"type" => "toggle", "text" => "15min:", "children" => []},
    %{"type" => "toggle", "text" => "daily:", "children" => []}
  ]

  @doc """
  Returns the hardcoded placeholder toggle blocks used when creating Notion placeholder pages.
  """
  def placeholder_blocks, do: @placeholder_blocks

  @doc """
  List all combined drafts with preloaded associations, ordered by creation time ascending.
  """
  @preloads [:metadata_draft, :writeup_draft, :trade]

  def list_drafts do
    from(d in Draft,
      order_by: [asc: d.inserted_at],
      preload: ^@preloads
    )
    |> Repo.all()
  end

  @doc """
  Get a single combined draft by id with preloaded associations. Returns nil if not found.
  """
  def get_draft(id) do
    Draft
    |> Repo.get(id)
    |> Repo.preload(@preloads)
  end

  @doc """
  Get a single combined draft by id with preloaded associations. Raises if not found.
  """
  def get_draft!(id) do
    Draft
    |> Repo.get!(id)
    |> Repo.preload(@preloads)
  end

  @doc """
  Create a new combined draft.
  """
  def create_draft(attrs) do
    %Draft{}
    |> Draft.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, draft} -> {:ok, Repo.preload(draft, @preloads)}
      error -> error
    end
  end

  @doc """
  Update an existing combined draft.
  """
  def update_draft(%Draft{} = draft, attrs) do
    draft
    |> Draft.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, draft} -> {:ok, Repo.preload(draft, @preloads, force: true)}
      error -> error
    end
  end

  @doc """
  Delete a combined draft.

  Options:
    - `:mode` - `:shallow` (default) or `:deep`
      - `:shallow` deletes only the combined draft record, leaving metadata and writeup drafts intact.
      - `:deep` also deletes associated metadata and writeup drafts if they are not referenced by
        any other combined draft. Preset writeup drafts are always preserved.

  `:shallow` returns `{:ok, %Draft{}}`.
  `:deep` returns `{:ok, %{combined_draft: draft, metadata_draft_deleted: bool, writeup_draft_deleted: bool}}`.
  """
  def delete_draft(%Draft{} = draft, opts \\ []) do
    case Keyword.get(opts, :mode, :shallow) do
      :shallow -> Repo.delete(draft)
      :deep -> deep_delete_draft(draft)
    end
  end

  @doc """
  Delete combined drafts by a list of ids.

  Options:
    - `:mode` - `:shallow` (default) or `:deep`
      - `:shallow` deletes only the combined draft records. Returns `{:ok, count}`.
      - `:deep` also prunes associated metadata and writeup drafts that are no longer referenced by
        any remaining combined draft. Returns
        `{:ok, %{combined_count: N, metadata_count: N, writeup_count: N}}`.
  """
  def delete_drafts(ids, opts \\ []) when is_list(ids) do
    case Keyword.get(opts, :mode, :shallow) do
      :shallow ->
        {count, _} = from(d in Draft, where: d.id in ^ids) |> Repo.delete_all()
        {:ok, count}

      :deep ->
        deep_delete_drafts(ids)
    end
  end

  @doc """
  Set the Notion page ID on a combined draft.
  """
  def set_notion_page_id(%Draft{} = draft, page_id) when is_binary(page_id) do
    draft
    |> Draft.changeset(%{notion_page_id: page_id})
    |> Repo.update()
  end

  @doc """
  Clear the Notion page ID from a combined draft.
  """
  def clear_notion_page_id(%Draft{} = draft) do
    draft
    |> Draft.changeset(%{notion_page_id: nil, applied_at: nil})
    |> Repo.update()
  end

  @doc """
  Mark a combined draft as applied by setting `applied_at` to now.
  """
  def mark_applied(%Draft{} = draft) do
    draft
    |> Draft.changeset(%{applied_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Bind a combined draft to a trade. Fails if the draft has already been pushed (applied_at set).
  """
  def bind_to_trade(%Draft{} = draft, trade_id) when is_integer(trade_id) do
    if draft.applied_at do
      {:error, :already_pushed}
    else
      draft
      |> Draft.changeset(%{trade_id: trade_id})
      |> Repo.update()
      |> case do
        {:ok, draft} -> {:ok, Repo.preload(draft, @preloads, force: true)}
        error -> error
      end
    end
  end

  @doc """
  Unbind a combined draft from its trade. Fails if the draft has been pushed (applied_at set).
  Does NOT revert the trade's metadata/writeup data.
  """
  def unbind_from_trade(%Draft{} = draft) do
    if draft.applied_at do
      {:error, :already_pushed}
    else
      draft
      |> Draft.changeset(%{trade_id: nil})
      |> Repo.update()
      |> case do
        {:ok, draft} -> {:ok, Repo.preload(draft, @preloads, force: true)}
        error -> error
      end
    end
  end

  @doc """
  Find the combined draft bound to a given trade. Returns nil if none.
  """
  def draft_for_trade(trade_id) when is_integer(trade_id) do
    from(d in Draft, where: d.trade_id == ^trade_id)
    |> Repo.one()
    |> case do
      nil -> nil
      draft -> Repo.preload(draft, @preloads)
    end
  end

  # ── Deep delete helpers ──────────────────────────────────────────────

  defp deep_delete_draft(%Draft{} = draft) do
    md_id = draft.metadata_draft_id
    wd_id = draft.writeup_draft_id

    Repo.transaction(fn ->
      case Repo.delete(draft) do
        {:ok, deleted} ->
          md_deleted = maybe_delete_orphan_metadata(md_id)
          wd_deleted = maybe_delete_orphan_writeup(wd_id)
          %{combined_draft: deleted, metadata_draft_deleted: md_deleted, writeup_draft_deleted: wd_deleted}

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp deep_delete_drafts([]) do
    {:ok, %{combined_count: 0, metadata_count: 0, writeup_count: 0}}
  end

  defp deep_delete_drafts(ids) do
    sub_ids =
      from(d in Draft,
        where: d.id in ^ids,
        select: {d.metadata_draft_id, d.writeup_draft_id}
      )
      |> Repo.all()

    md_ids = sub_ids |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    wd_ids = sub_ids |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Repo.transaction(fn ->
      {count, _} = from(d in Draft, where: d.id in ^ids) |> Repo.delete_all()

      md_deleted =
        Enum.count(md_ids, fn md_id ->
          remaining =
            Repo.one(from d in Draft, where: d.metadata_draft_id == ^md_id, select: count(d.id))

          if remaining == 0, do: delete_metadata_draft_by_id(md_id), else: false
        end)

      wd_deleted =
        Enum.count(wd_ids, fn wd_id ->
          remaining =
            Repo.one(from d in Draft, where: d.writeup_draft_id == ^wd_id, select: count(d.id))

          if remaining == 0, do: delete_writeup_draft_by_id(wd_id), else: false
        end)

      %{combined_count: count, metadata_count: md_deleted, writeup_count: wd_deleted}
    end)
  end

  defp maybe_delete_orphan_metadata(nil), do: false

  defp maybe_delete_orphan_metadata(md_id) do
    remaining =
      Repo.one(from d in Draft, where: d.metadata_draft_id == ^md_id, select: count(d.id))

    if remaining == 0, do: delete_metadata_draft_by_id(md_id), else: false
  end

  defp maybe_delete_orphan_writeup(nil), do: false

  defp maybe_delete_orphan_writeup(wd_id) do
    remaining =
      Repo.one(from d in Draft, where: d.writeup_draft_id == ^wd_id, select: count(d.id))

    if remaining == 0, do: delete_writeup_draft_by_id(wd_id), else: false
  end

  defp delete_metadata_draft_by_id(id) do
    case MetadataDrafts.get_draft(id) do
      nil -> false
      draft -> match?({:ok, _}, MetadataDrafts.delete_draft(draft))
    end
  end

  defp delete_writeup_draft_by_id(id) do
    case WriteupDrafts.get_draft(id) do
      nil -> false
      %{is_preset: true} -> false
      draft -> match?({:ok, _}, WriteupDrafts.delete_draft(draft))
    end
  end
end

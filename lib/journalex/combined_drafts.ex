defmodule Journalex.CombinedDrafts do
  @moduledoc """
  Context for managing combined draft templates that pair metadata + writeup drafts.
  """
  @behaviour Journalex.CombinedDraftsBehaviour

  import Ecto.Query, warn: false
  alias Journalex.Repo
  alias Journalex.CombinedDrafts.Draft

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
  """
  def delete_draft(%Draft{} = draft) do
    Repo.delete(draft)
  end

  @doc """
  Delete all combined drafts by a list of ids.
  Returns `{:ok, count}` with the number of deleted rows.
  """
  def delete_drafts(ids) when is_list(ids) do
    {count, _} = from(d in Draft, where: d.id in ^ids) |> Repo.delete_all()
    {:ok, count}
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
end

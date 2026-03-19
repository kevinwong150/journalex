defmodule Journalex.CombinedDrafts do
  @moduledoc """
  Context for managing combined draft templates that pair metadata + writeup drafts.
  """
  @behaviour Journalex.CombinedDraftsBehaviour

  import Ecto.Query, warn: false
  alias Journalex.Repo
  alias Journalex.CombinedDrafts.Draft

  @doc """
  List all combined drafts with preloaded associations, ordered by creation time ascending.
  """
  def list_drafts do
    from(d in Draft,
      order_by: [asc: d.inserted_at],
      preload: [:metadata_draft, :writeup_draft]
    )
    |> Repo.all()
  end

  @doc """
  Get a single combined draft by id with preloaded associations. Returns nil if not found.
  """
  def get_draft(id) do
    Draft
    |> Repo.get(id)
    |> Repo.preload([:metadata_draft, :writeup_draft])
  end

  @doc """
  Get a single combined draft by id with preloaded associations. Raises if not found.
  """
  def get_draft!(id) do
    Draft
    |> Repo.get!(id)
    |> Repo.preload([:metadata_draft, :writeup_draft])
  end

  @doc """
  Create a new combined draft.
  """
  def create_draft(attrs) do
    %Draft{}
    |> Draft.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, draft} -> {:ok, Repo.preload(draft, [:metadata_draft, :writeup_draft])}
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
      {:ok, draft} -> {:ok, Repo.preload(draft, [:metadata_draft, :writeup_draft], force: true)}
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
end

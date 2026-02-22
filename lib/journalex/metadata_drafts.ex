defmodule Journalex.MetadataDrafts do
  @moduledoc """
  Context for managing named metadata draft templates.
  """
  import Ecto.Query, warn: false
  alias Journalex.Repo
  alias Journalex.MetadataDrafts.Draft

  @doc """
  List all drafts, ordered by name ascending.
  """
  def list_drafts do
    from(d in Draft, order_by: [asc: d.name])
    |> Repo.all()
  end

  @doc """
  List drafts for a specific metadata version.
  """
  def list_drafts_by_version(version) when is_integer(version) do
    from(d in Draft, where: d.metadata_version == ^version, order_by: [asc: d.name])
    |> Repo.all()
  end

  @doc """
  Get a single draft by id. Raises if not found.
  """
  def get_draft!(id), do: Repo.get!(Draft, id)

  @doc """
  Get a single draft by id. Returns nil if not found.
  """
  def get_draft(id), do: Repo.get(Draft, id)

  @doc """
  Create a new draft.
  """
  def create_draft(attrs) do
    %Draft{}
    |> Draft.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing draft.
  """
  def update_draft(%Draft{} = draft, attrs) do
    draft
    |> Draft.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a draft.
  """
  def delete_draft(%Draft{} = draft) do
    Repo.delete(draft)
  end
end

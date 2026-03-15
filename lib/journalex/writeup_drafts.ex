defmodule Journalex.WriteupDrafts do
  @moduledoc """
  Context for managing named writeup draft templates.
  """
  import Ecto.Query, warn: false
  alias Journalex.Repo
  alias Journalex.WriteupDrafts.Draft

  @doc """
  List all writeup drafts, ordered by creation time ascending (oldest first).
  """
  def list_drafts do
    from(d in Draft, order_by: [asc: d.inserted_at])
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
    case Repo.get_by(Draft, is_preset: true) do
      %Draft{} ->
        :ok

      nil ->
        %Draft{}
        |> Draft.changeset(%{name: @preset_name, blocks: @preset_blocks, is_preset: true})
        |> Repo.insert(on_conflict: :nothing)

        :ok
    end
  end
end

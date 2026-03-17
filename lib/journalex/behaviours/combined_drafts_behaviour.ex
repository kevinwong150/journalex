defmodule Journalex.CombinedDraftsBehaviour do
  @moduledoc """
  Behaviour for CombinedDrafts context, enabling Mox testability.
  """
  alias Journalex.CombinedDrafts.Draft

  @callback list_drafts() :: [%Draft{}]
  @callback get_draft(integer()) :: %Draft{} | nil
  @callback get_draft!(integer()) :: %Draft{}
  @callback create_draft(map()) :: {:ok, %Draft{}} | {:error, Ecto.Changeset.t()}
  @callback update_draft(%Draft{}, map()) :: {:ok, %Draft{}} | {:error, Ecto.Changeset.t()}
  @callback delete_draft(%Draft{}) :: {:ok, %Draft{}} | {:error, Ecto.Changeset.t()}
end

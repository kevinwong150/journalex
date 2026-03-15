defmodule Journalex.WriteupDraftsBehaviour do
  @moduledoc """
  Behaviour for WriteupDrafts context, enabling Mox testability.
  """
  alias Journalex.WriteupDrafts.Draft

  @callback list_drafts() :: [Draft.t()]
  @callback get_draft!(integer()) :: Draft.t()
  @callback get_draft(integer()) :: Draft.t() | nil
  @callback create_draft(map()) :: {:ok, Draft.t()} | {:error, Ecto.Changeset.t()}
  @callback update_draft(Draft.t(), map()) :: {:ok, Draft.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_draft(Draft.t()) :: {:ok, Draft.t()} | {:error, Ecto.Changeset.t()}
end

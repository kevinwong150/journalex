defmodule Journalex.ActivityBehaviour do
  @moduledoc """
  Behaviour for the Activity context, enabling Mox-based testing.
  Only includes functions called by the upload-result LiveView.
  """

  @callback dedupe_by_datetime_symbol(list()) :: list()
  @callback rows_exist_flags(list()) :: list()
  @callback save_activity_rows(list()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback save_activity_row(map()) :: {:ok, term()} | {:error, term()}
  @callback list_activity_statements_between(Date.t(), Date.t(), keyword()) :: list()
end

defmodule JournalexWeb.NavHelpers do
  @moduledoc """
  Small helpers used by the layout/navigation.

  Currently provides a check to see whether there are any uploaded CSV files
  under priv/uploads so we can enable/disable related navigation affordances.
  """

  @doc """
  Returns true if at least one .csv file exists under priv/uploads.
  """
  @spec uploads_present?() :: boolean()
  def uploads_present? do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()

    case File.ls(uploads_dir) do
      {:ok, files} -> Enum.any?(files, &String.ends_with?(&1, ".csv"))
      _ -> false
    end
  rescue
    _ -> false
  end
end

defmodule JournalexWeb.NavHelpers do
  @moduledoc """
  Small helpers used by the layout/navigation.

  Provides:
  - The full page registry (`all_pages/0`)
  - Pinned nav shortcuts (`nav_pinned_pages/0`) driven by user settings
  - Upload file detection (`uploads_present?/0`)
  """

  alias Journalex.Settings

  # Registry of all navigable pages: {key, label, path}
  @all_pages [
    {"trade_dump",         "Trades Dump",        "/trade/dump"},
    {"trade_drafts",       "Trade Drafts",       "/trade/drafts"},
    {"metadata_drafts",    "Metadata Drafts",    "/trade/drafts/metadata"},
    {"writeup_drafts",     "Writeup Drafts",     "/trade/drafts/writeups"},
    {"all_trades",         "All Trades",         "/trade/all"},
    {"trades_by_date",     "Trades by Date",     "/trade/dates"},
    {"all_statements",     "All Statements",     "/activity_statement/all"},
    {"statements_by_date", "Statements by Date", "/activity_statement/dates"},
    {"statement_dump",     "Statement Dump",     "/statement/dump"},
    {"upload",             "Upload",             "/activity_statement/upload"},
    {"settings",           "Settings",           "/settings"}
  ]

  @doc """
  Returns the full page registry as a list of {key, label, path} tuples.
  """
  @spec all_pages() :: [{String.t(), String.t(), String.t()}]
  def all_pages, do: @all_pages

  @doc """
  Returns [{label, path}] for the pages the user has pinned to the nav bar,
  in the order they were pinned.
  """
  @spec nav_pinned_pages() :: [{String.t(), String.t()}]
  def nav_pinned_pages do
    pinned_keys = Settings.get_nav_pinned_pages()
    page_map = Map.new(@all_pages, fn {key, label, path} -> {key, {label, path}} end)

    Enum.flat_map(pinned_keys, fn key ->
      case Map.get(page_map, key) do
        nil -> []
        {label, path} -> [{label, path}]
      end
    end)
  end

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

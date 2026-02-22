defmodule Journalex.TestFixtures do
  @moduledoc """
  Helpers for locating test fixture files.
  """

  @fixtures_dir Path.expand("../fixtures", __DIR__)

  @doc "Return absolute path to a fixture file under test/fixtures/."
  def fixture_path(relative) do
    Path.join(@fixtures_dir, relative)
  end

  @doc "Return absolute path to a fixture CSV in test/fixtures/uploads/."
  def upload_fixture(filename) do
    fixture_path(Path.join("uploads", filename))
  end

  @doc "No-trades day CSV (Jan 28, 2026)."
  def no_trades_csv, do: upload_fixture("no_trades_day.csv")

  @doc "Single-ticker trades CSV — COIN open/close (Feb 4, 2026)."
  def single_ticker_csv, do: upload_fixture("single_ticker_trades.csv")

  @doc "Multi-ticker trades CSV — CRM, JPM, PYPL, V (Feb 9, 2026)."
  def multi_ticker_csv, do: upload_fixture("multi_ticker_trades.csv")
end

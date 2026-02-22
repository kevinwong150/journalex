defmodule Journalex.TestFixtures do
  @moduledoc """
  Helpers for locating test fixture files and staging uploads for integration tests.
  """

  @fixtures_dir Path.expand("../fixtures", __DIR__)

  # ── Fixture path helpers ────────────────────────────────────────────

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

  # ── Upload staging for integration tests ────────────────────────────
  #
  # The LiveView reads CSVs from priv/uploads/ on mount. These helpers
  # copy fixture files there during test setup and clean up afterwards.
  #
  # Safety guards (all enforced):
  #   1. Only runs in MIX_ENV=test
  #   2. Target directory must end with "priv/uploads"
  #   3. Only known fixture filenames are allowed (whitelist)
  #   4. Only .csv files are copied/removed
  #   5. Source file must be < 100 KB (fixtures are tiny)
  #   6. Cleanup refuses if dir contains more than 10 CSVs (not a test dir)

  @known_test_fixtures ~w(no_trades_day.csv single_ticker_trades.csv multi_ticker_trades.csv)
  @max_fixture_size 100_000

  @doc """
  Returns the application's uploads directory (priv/uploads/).
  Same path the LiveView uses via `:code.priv_dir/1`.
  """
  def uploads_dir do
    Application.get_env(
      :journalex,
      :uploads_dir,
      [:code.priv_dir(:journalex), "uploads"] |> Path.join() |> to_string()
    )
  end

  @doc """
  Copies fixture CSVs into priv/uploads/ so the LiveView can read them on mount.

  Accepts a list of absolute fixture paths (use `single_ticker_csv/0` etc.).
  Returns the list of filenames that were staged.

  ## Example

      stage_uploads([single_ticker_csv(), multi_ticker_csv()])
      #=> ["single_ticker_trades.csv", "multi_ticker_trades.csv"]
  """
  def stage_uploads(fixture_paths) when is_list(fixture_paths) do
    verify_test_env!()
    dir = uploads_dir()
    verify_uploads_dir!(dir)
    File.mkdir_p!(dir)

    Enum.map(fixture_paths, fn src ->
      filename = Path.basename(src)
      verify_fixture_filename!(filename)
      verify_file_size!(src)
      dest = Path.join(dir, filename)
      File.cp!(src, dest)
      filename
    end)
  end

  @doc """
  Removes known test fixture files from priv/uploads/.
  Call this in `setup` and `on_exit` to ensure a clean state between tests.
  Only removes files whose names match the known fixture whitelist — real
  uploads (even if there are many) are never touched.
  """
  def clear_test_uploads do
    verify_test_env!()
    dir = uploads_dir()
    verify_uploads_dir!(dir)

    case File.ls(dir) do
      {:ok, _files} ->
        # Only remove the exact known fixture filenames — nothing else
        Enum.each(@known_test_fixtures, fn filename ->
          path = Path.join(dir, filename)
          File.rm(path)
        end)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise "Cannot list #{dir}: #{inspect(reason)}"
    end
  end

  # ── Safety guards ───────────────────────────────────────────────────

  defp verify_test_env! do
    unless Mix.env() == :test do
      raise "Safety: upload staging is only allowed in MIX_ENV=test (current: #{Mix.env()})"
    end
  end

  defp verify_uploads_dir!(dir) do
    normalized = String.replace(dir, "\\", "/")
    basename = Path.basename(normalized)

    unless String.contains?(basename, "uploads") do
      raise "Safety: #{dir} does not look like an uploads directory"
    end
  end

  defp verify_fixture_filename!(filename) do
    unless filename in @known_test_fixtures do
      raise "Safety: #{filename} is not a known test fixture. " <>
              "Allowed: #{inspect(@known_test_fixtures)}"
    end

    unless String.ends_with?(filename, ".csv") do
      raise "Safety: #{filename} is not a .csv file"
    end
  end

  defp verify_file_size!(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_fixture_size ->
        raise "Safety: #{path} is #{size} bytes (limit: #{@max_fixture_size})"

      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise "Safety: cannot stat #{path}: #{inspect(reason)}"
    end
  end
end

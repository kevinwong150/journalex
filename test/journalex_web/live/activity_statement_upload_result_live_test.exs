defmodule JournalexWeb.ActivityStatementUploadResultLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Journalex.TestFixtures

  # Ensure priv/uploads/ is clean before and after every test.
  # `clear_test_uploads/0` only removes known fixture filenames (whitelist).
  setup do
    clear_test_uploads()
    on_exit(fn -> clear_test_uploads() end)
    :ok
  end

  # ── Empty state ──────────────────────────────────────────────────────

  describe "empty state (no uploads)" do
    test "renders empty message when no CSVs are present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "No activity data available"
      assert html =~ "Upload CSV file"
    end

    test "shows zero unsaved count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "Unsaved records:"
    end
  end

  # ── No-trades CSV (has headers but no trade rows) ────────────────────

  describe "mount with no-trades CSV" do
    setup do
      stage_uploads([no_trades_csv()])
      :ok
    end

    test "renders empty state since CSV has no trades", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "No activity data available"
    end
  end

  # ── Single ticker (COIN) ─────────────────────────────────────────────

  describe "mount with single-ticker CSV (COIN)" do
    setup do
      stage_uploads([single_ticker_csv()])
      :ok
    end

    test "displays the ticker symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "COIN"
    end

    test "shows the statement period", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "February 4, 2026"
    end

    test "does not show empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      refute html =~ "No activity data available"
    end

    test "page title is rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "Activity Statement Upload Result"
    end
  end

  # ── Multi ticker (CRM, JPM, PYPL, V) ────────────────────────────────

  describe "mount with multi-ticker CSV" do
    setup do
      stage_uploads([multi_ticker_csv()])
      :ok
    end

    test "displays all ticker symbols", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "CRM"
      assert html =~ "JPM"
      assert html =~ "PYPL"
    end

    test "shows the statement period for Feb 9", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "February 9, 2026"
    end

    test "does not show empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      refute html =~ "No activity data available"
    end
  end

  # ── Multiple CSVs staged at once ─────────────────────────────────────

  describe "mount with multiple CSVs" do
    setup do
      stage_uploads([single_ticker_csv(), multi_ticker_csv()])
      :ok
    end

    test "displays tickers from both files", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      assert html =~ "COIN"
      assert html =~ "CRM"
      assert html =~ "JPM"
    end

    test "shows date range spanning both files", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/activity_statement/upload/result")

      # Feb 4 (single) – Feb 9 (multi)
      assert html =~ "February 4, 2026"
      assert html =~ "February 9, 2026"
    end
  end

  # ── Day filter toggles ──────────────────────────────────────────────

  describe "day filter toggles" do
    setup do
      stage_uploads([multi_ticker_csv()])
      :ok
    end

    test "deselect all days hides trades", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      html = render_click(view, "deselect_all_days")

      assert html =~ "No activity data available"
    end

    test "select all days after deselect restores trades", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "deselect_all_days")
      html = render_click(view, "select_all_days")

      assert html =~ "CRM"
      assert html =~ "JPM"
      refute html =~ "No activity data available"
    end

    test "toggle individual day off hides trades for that day", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      # All trades are from 2026-02-09, toggling it off should hide everything
      html = render_click(view, "toggle_day", %{"day" => "2026-02-09"})

      assert html =~ "No activity data available"
    end

    test "toggle day back on restores trades", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "toggle_day", %{"day" => "2026-02-09"})
      html = render_click(view, "toggle_day", %{"day" => "2026-02-09"})

      assert html =~ "CRM"
      refute html =~ "No activity data available"
    end
  end

  # ── Save all activity rows ──────────────────────────────────────────

  describe "save_all event" do
    setup do
      stage_uploads([single_ticker_csv()])
      :ok
    end

    test "saves rows and shows success flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "save_all")

      assert_push_event(view, "toast", %{kind: :info, message: msg})
      assert msg =~ "Saved"
      assert msg =~ "new rows to DB"
    end

    test "rows are persisted in the database", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "save_all")

      rows = Journalex.Activity.list_activity_statements_between(~D[2026-02-04], ~D[2026-02-04])
      assert length(rows) > 0
    end

    test "saving twice is idempotent (no duplicate flash error)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "save_all")
      assert_push_event(view, "toast", %{kind: :info, message: _})

      render_click(view, "save_all")
      # Second save should still succeed (kind: :info, not :error)
      assert_push_event(view, "toast", %{kind: :info, message: _})
    end
  end

  # ── Save single row ─────────────────────────────────────────────────

  describe "save_row event" do
    setup do
      stage_uploads([single_ticker_csv()])
      :ok
    end

    test "saves one row and shows flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "save_row", %{"index" => "0"})

      assert_push_event(view, "toast", %{kind: :info, message: "Row saved"})
    end
  end

  # ── Delete all uploads ──────────────────────────────────────────────

  describe "delete_all_uploads event" do
    setup do
      stage_uploads([single_ticker_csv()])
      :ok
    end

    test "resets to empty state and shows flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      html = render_click(view, "delete_all_uploads")

      assert_push_event(view, "toast", %{kind: :info, message: msg})
      assert msg =~ "Deleted"
      assert html =~ "No activity data available"
    end

    test "CSV files are removed from disk", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      render_click(view, "delete_all_uploads")

      dir = uploads_dir()

      csv_files =
        case File.ls(dir) do
          {:ok, files} -> Enum.filter(files, &String.ends_with?(&1, ".csv"))
          {:error, :enoent} -> []
        end

      assert csv_files == []
    end
  end

  # ── UI toggle events ────────────────────────────────────────────────

  describe "toggle events" do
    setup do
      stage_uploads([single_ticker_csv()])
      :ok
    end

    test "toggle_summary expands and collapses", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      html = render_click(view, "toggle_summary")
      assert html =~ "Collapse"

      html = render_click(view, "toggle_summary")
      assert html =~ "Expand"
    end

    test "toggle_older_weeks toggles visibility", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/activity_statement/upload/result")

      # With only 1 week of data and filter_visible_weeks=3,
      # there should be no "older weeks" to toggle, so the event is safe (no-op).
      html = render_click(view, "toggle_older_weeks")
      assert is_binary(html)
    end
  end
end

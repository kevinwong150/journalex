defmodule JournalexWeb.SettingsLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Journalex.Settings

  test "saves analytics exception days from the settings page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")

    assert html =~ "Exception Days"

    render_click(view, "add_exception_day")

    html =
      render_submit(view, "save_settings", %{
        "settings" => %{
          "default_metadata_version" => "3",
          "auto_check_on_load" => "true",
          "r_size" => "10",
          "activity_page_size" => "20",
          "filter_visible_weeks" => "3",
          "summary_period_value" => "3",
          "summary_period_unit" => "week",
          "nav_pinned_pages" => %{},
          "analytics_exception_days" => ["2026-06-01", "2026-06-02"]
        }
      })

    assert html =~ "Saved!"
    assert Settings.get_analytics_exception_days() == [~D[2026-06-01], ~D[2026-06-02]]
  end
end
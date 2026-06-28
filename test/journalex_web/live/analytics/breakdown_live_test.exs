defmodule JournalexWeb.Analytics.BreakdownLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders multi-select tabs and switches to them", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/analytics/breakdown")

    assert html =~ "Patterns"
    assert html =~ "Regular Lessons"
    assert has_element?(view, "button[phx-value-tab=\"patterns\"]")
    assert has_element?(view, "button[phx-value-tab=\"regular_lessons\"]")

    view
    |> element("button[phx-value-tab=\"patterns\"]")
    |> render_click()

    assert has_element?(view, "th", "Patterns")
  end
end
defmodule JournalexWeb.Analytics.CompareLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "shows exception-day banner on the compare page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/analytics/compare")

    assert html =~ "Exception days:"
    assert html =~ "Excluding exception days"
  end
end

defmodule JournalexWeb.TradeDraftLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Journalex.WriteupDrafts

  describe "bulk create selectors" do
    test "selected metadata version survives row add and remove", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/trade/drafts")

      view
      |> element("button[phx-click=\"toggle_bulk\"]")
      |> render_click()

      view
      |> element("form[phx-change=\"bulk_set_version\"]")
      |> render_change(%{"version" => "2"})

      assert has_element?(view, "select[name=\"version\"] option[value=\"2\"][selected]")

      view
      |> element("button[phx-click=\"bulk_add_row\"]")
      |> render_click()

      assert has_element?(view, "select[name=\"version\"] option[value=\"2\"][selected]")

      view
      |> element("button[phx-click=\"bulk_remove_row\"]")
      |> render_click()

      assert has_element?(view, "select[name=\"version\"] option[value=\"2\"][selected]")
    end

    test "selected writeup template survives row add and remove", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/trade/drafts")

      view
      |> element("button[phx-click=\"toggle_bulk\"]")
      |> render_click()

      preset =
        WriteupDrafts.list_preset_drafts()
        |> hd()

      view
      |> element("form[phx-change=\"bulk_set_writeup_template\"]")
      |> render_change(%{"template_id" => Integer.to_string(preset.id)})

      assert has_element?(
               view,
               "select[name=\"template_id\"] option[value=\"#{preset.id}\"][selected]"
             )

      view
      |> element("button[phx-click=\"bulk_add_row\"]")
      |> render_click()

      assert has_element?(
               view,
               "select[name=\"template_id\"] option[value=\"#{preset.id}\"][selected]"
             )

      view
      |> element("button[phx-click=\"bulk_remove_row\"]")
      |> render_click()

      assert has_element?(
               view,
               "select[name=\"template_id\"] option[value=\"#{preset.id}\"][selected]"
             )
    end
  end
end

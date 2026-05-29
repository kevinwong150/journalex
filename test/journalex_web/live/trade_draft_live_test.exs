defmodule JournalexWeb.TradeDraftLiveTest do
  use JournalexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Journalex.CombinedDrafts
  alias Journalex.MetadataDrafts
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

  describe "v3 metadata form" do
    test "keeps unsaved selections when progression chain updates", %{conn: conn} do
      {:ok, metadata_draft} =
        MetadataDrafts.create_draft(%{
          name: "V3 Metadata Draft",
          metadata_version: 3,
          metadata: %{},
          journal_data: %{}
        })

      {:ok, combined_draft} =
        CombinedDrafts.create_draft(%{
          name: "Combined V3 Draft",
          metadata_draft_id: metadata_draft.id
        })

      {:ok, view, _html} = live(conn, ~p"/trade/drafts")

      view
      |> element("div[phx-click=\"select_draft\"][phx-value-id=\"#{combined_draft.id}\"]")
      |> render_click()

      view
      |> element("form[phx-change=\"metadata_changed\"]")
      |> render_change(%{
        "setup" => "Testing Setup",
        "follow_up_trial" => "true",
        "close_time_comment" => ["Normal Entry and Close"]
      })

      view
      |> element("button[phx-click=\"v3_chain_add_token\"][phx-value-token=\"ENTRY\"]")
      |> render_click()

      assert has_element?(view, "select[name=\"setup\"] option[value=\"Testing Setup\"][selected]")
      assert has_element?(view, "input[name=\"follow_up_trial\"][checked]")
      assert has_element?(view, "input[name=\"close_time_comment[]\"][value=\"Normal Entry and Close\"][checked]")
      assert render(view) =~ "ENTRY"
    end
  end
end

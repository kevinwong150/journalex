defmodule Journalex.NotionTest do
  use ExUnit.Case, async: true

  alias Journalex.Notion

  describe "compute_entry_timeslot/1 and compute_close_timeslot/1" do
    test "maps trades after 16:00 into the live V3 Notion slots through 17:00" do
      row = %{
        action_chain: %{
          "1" => %{"datetime" => "2026-05-24T16:05:00Z"},
          "2" => %{"action" => "close_position", "datetime" => "2026-05-24T16:35:00Z"}
        }
      }

      assert Notion.compute_entry_timeslot(row) == "1600-1630"
      assert Notion.compute_close_timeslot(row) == "1630-1700"
    end
  end
end

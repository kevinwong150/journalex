defmodule Journalex.SettingsTest do
  use Journalex.DataCase, async: true

  alias Journalex.Settings

  describe "analytics exception days" do
    test "normalizes blank, duplicate, and unsorted dates" do
      assert {:ok, _} =
               Settings.set_analytics_exception_days([
                 "2026-01-03",
                 "",
                 "2026-01-01",
                 "2026-01-03",
                 ~D[2026-01-02]
               ])

      assert Settings.get_analytics_exception_days() == [
               ~D[2026-01-01],
               ~D[2026-01-02],
               ~D[2026-01-03]
             ]
    end

    test "rejects invalid date strings" do
      assert {:error, :invalid_exception_days} =
               Settings.set_analytics_exception_days(["not-a-date"])
    end
  end
end
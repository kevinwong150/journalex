defmodule Journalex.CombinedDraftsTest do
  use Journalex.DataCase, async: true

  alias Journalex.CombinedDrafts
  alias Journalex.MetadataDrafts
  alias Journalex.WriteupDrafts

  defp create_metadata_draft(name \\ "Meta Draft") do
    {:ok, draft} = MetadataDrafts.create_draft(%{name: name, metadata_version: 2, metadata: %{}})
    draft
  end

  defp create_writeup_draft(name \\ "Writeup Draft") do
    {:ok, draft} = WriteupDrafts.create_draft(%{name: name, blocks: []})
    draft
  end

  describe "create_draft/1" do
    test "creates a combined draft with both references" do
      md = create_metadata_draft()
      wd = create_writeup_draft()

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{
                 name: "Full Combo",
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert draft.name == "Full Combo"
      assert draft.metadata_draft.id == md.id
      assert draft.writeup_draft.id == wd.id
    end

    test "creates a combined draft with metadata only" do
      md = create_metadata_draft()

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{name: "Meta Only", metadata_draft_id: md.id})

      assert draft.metadata_draft.id == md.id
      assert is_nil(draft.writeup_draft)
    end

    test "creates a combined draft with writeup only" do
      wd = create_writeup_draft()

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{name: "Writeup Only", writeup_draft_id: wd.id})

      assert is_nil(draft.metadata_draft)
      assert draft.writeup_draft.id == wd.id
    end

    test "creates a combined draft with no references" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Empty Combo"})
      assert is_nil(draft.metadata_draft)
      assert is_nil(draft.writeup_draft)
    end

    test "fails without name" do
      assert {:error, changeset} = CombinedDrafts.create_draft(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with duplicate name" do
      assert {:ok, _} = CombinedDrafts.create_draft(%{name: "Dup"})
      assert {:error, changeset} = CombinedDrafts.create_draft(%{name: "Dup"})
      assert %{name: ["a combined draft with this name already exists"]} = errors_on(changeset)
    end

    test "name too long is rejected" do
      long_name = String.duplicate("a", 101)
      assert {:error, changeset} = CombinedDrafts.create_draft(%{name: long_name})
      assert %{name: [_msg]} = errors_on(changeset)
    end
  end

  describe "list_drafts/0" do
    test "returns all combined drafts with preloaded associations" do
      md = create_metadata_draft()
      wd = create_writeup_draft()
      assert {:ok, _} = CombinedDrafts.create_draft(%{name: "A", metadata_draft_id: md.id})
      assert {:ok, _} = CombinedDrafts.create_draft(%{name: "B", writeup_draft_id: wd.id})

      drafts = CombinedDrafts.list_drafts()
      assert length(drafts) == 2
      assert Enum.all?(drafts, &Ecto.assoc_loaded?(&1.metadata_draft))
      assert Enum.all?(drafts, &Ecto.assoc_loaded?(&1.writeup_draft))
    end

    test "returns empty list when no combined drafts" do
      assert CombinedDrafts.list_drafts() == []
    end
  end

  describe "get_draft/1" do
    test "returns the combined draft with preloaded associations" do
      md = create_metadata_draft()

      assert {:ok, created} =
               CombinedDrafts.create_draft(%{name: "Test", metadata_draft_id: md.id})

      fetched = CombinedDrafts.get_draft(created.id)
      assert fetched.id == created.id
      assert fetched.metadata_draft.id == md.id
    end

    test "returns nil for non-existent id" do
      assert is_nil(CombinedDrafts.get_draft(0))
    end
  end

  describe "get_draft!/1" do
    test "returns the combined draft" do
      assert {:ok, created} = CombinedDrafts.create_draft(%{name: "Test"})
      assert CombinedDrafts.get_draft!(created.id).id == created.id
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        CombinedDrafts.get_draft!(0)
      end
    end
  end

  describe "update_draft/2" do
    test "updates name" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Original"})
      assert {:ok, updated} = CombinedDrafts.update_draft(draft, %{name: "Renamed"})
      assert updated.name == "Renamed"
    end

    test "updates references" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Test"})
      md = create_metadata_draft()
      wd = create_writeup_draft()

      assert {:ok, updated} =
               CombinedDrafts.update_draft(draft, %{
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert updated.metadata_draft.id == md.id
      assert updated.writeup_draft.id == wd.id
    end

    test "clears references by setting to nil" do
      md = create_metadata_draft()

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{name: "Test", metadata_draft_id: md.id})

      assert {:ok, updated} = CombinedDrafts.update_draft(draft, %{metadata_draft_id: nil})
      assert is_nil(updated.metadata_draft)
    end

    test "fails with invalid attrs" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Test"})
      assert {:error, changeset} = CombinedDrafts.update_draft(draft, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_draft/1" do
    test "deletes the combined draft" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "ToDelete"})
      assert {:ok, _} = CombinedDrafts.delete_draft(draft)
      assert is_nil(CombinedDrafts.get_draft(draft.id))
    end
  end

  describe "nilify on referenced draft deletion" do
    test "nilifies metadata_draft_id when metadata draft is deleted" do
      md = create_metadata_draft()

      assert {:ok, combo} =
               CombinedDrafts.create_draft(%{name: "Combo", metadata_draft_id: md.id})

      assert {:ok, _} = MetadataDrafts.delete_draft(md)

      refreshed = CombinedDrafts.get_draft(combo.id)
      assert is_nil(refreshed.metadata_draft_id)
      assert is_nil(refreshed.metadata_draft)
    end

    test "nilifies writeup_draft_id when writeup draft is deleted" do
      wd = create_writeup_draft()

      assert {:ok, combo} =
               CombinedDrafts.create_draft(%{name: "Combo", writeup_draft_id: wd.id})

      assert {:ok, _} = WriteupDrafts.delete_draft(wd)

      refreshed = CombinedDrafts.get_draft(combo.id)
      assert is_nil(refreshed.writeup_draft_id)
      assert is_nil(refreshed.writeup_draft)
    end
  end
end

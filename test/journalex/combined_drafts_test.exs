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

  describe "set_notion_page_id/2" do
    test "sets the notion_page_id on a draft" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Test"})
      assert {:ok, updated} = CombinedDrafts.set_notion_page_id(draft, "abc-123-def")
      assert updated.notion_page_id == "abc-123-def"
    end

    test "enforces unique constraint on notion_page_id" do
      assert {:ok, d1} = CombinedDrafts.create_draft(%{name: "Draft1"})
      assert {:ok, d2} = CombinedDrafts.create_draft(%{name: "Draft2"})
      assert {:ok, _} = CombinedDrafts.set_notion_page_id(d1, "unique-id-123")
      assert {:error, changeset} = CombinedDrafts.set_notion_page_id(d2, "unique-id-123")
      assert %{notion_page_id: ["another draft is already linked to this Notion page"]} = errors_on(changeset)
    end
  end

  describe "clear_notion_page_id/1" do
    test "clears notion_page_id and applied_at" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Test"})
      assert {:ok, linked} = CombinedDrafts.set_notion_page_id(draft, "page-id-456")
      assert {:ok, marked} = CombinedDrafts.mark_applied(linked)
      assert not is_nil(marked.applied_at)

      assert {:ok, cleared} = CombinedDrafts.clear_notion_page_id(marked)
      assert is_nil(cleared.notion_page_id)
      assert is_nil(cleared.applied_at)
    end
  end

  describe "mark_applied/1" do
    test "sets applied_at timestamp" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Test"})
      assert {:ok, linked} = CombinedDrafts.set_notion_page_id(draft, "page-id-789")
      assert {:ok, applied} = CombinedDrafts.mark_applied(linked)
      assert %DateTime{} = applied.applied_at
    end
  end

  describe "placeholder_blocks/0" do
    test "returns the hardcoded toggle blocks" do
      blocks = CombinedDrafts.placeholder_blocks()
      assert length(blocks) == 5
      assert Enum.all?(blocks, &(&1["type"] == "toggle"))
      texts = Enum.map(blocks, & &1["text"])
      assert texts == ["1min:", "2min:", "5min:", "15min:", "daily:"]
    end
  end

  describe "delete_draft/2 (mode: :shallow)" do
    test "deletes the combined draft, leaving sub-drafts intact" do
      md = create_metadata_draft()
      wd = create_writeup_draft()

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{
                 name: "ToDelete",
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert {:ok, _} = CombinedDrafts.delete_draft(draft, mode: :shallow)

      assert is_nil(CombinedDrafts.get_draft(draft.id))
      assert MetadataDrafts.get_draft(md.id) != nil
      assert WriteupDrafts.get_draft(wd.id) != nil
    end

    test "default (no opts) behaves as shallow" do
      md = create_metadata_draft("Meta Default")
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "Def", metadata_draft_id: md.id})

      assert {:ok, _} = CombinedDrafts.delete_draft(draft)

      assert is_nil(CombinedDrafts.get_draft(draft.id))
      assert MetadataDrafts.get_draft(md.id) != nil
    end
  end

  describe "delete_draft/2 (mode: :deep)" do
    test "deletes the combined draft and its sub-drafts when unreferenced" do
      md = create_metadata_draft("Orphan Meta")
      wd = create_writeup_draft("Orphan Writeup")

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{
                 name: "DeepDelete",
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert {:ok, result} = CombinedDrafts.delete_draft(draft, mode: :deep)
      assert result.metadata_draft_deleted == true
      assert result.writeup_draft_deleted == true

      assert is_nil(CombinedDrafts.get_draft(draft.id))
      assert is_nil(MetadataDrafts.get_draft(md.id))
      assert is_nil(WriteupDrafts.get_draft(wd.id))
    end

    test "preserves sub-drafts shared by another combined draft" do
      md = create_metadata_draft("Shared Meta")
      wd = create_writeup_draft("Shared Writeup")

      assert {:ok, draft1} =
               CombinedDrafts.create_draft(%{
                 name: "Owner1",
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert {:ok, _draft2} =
               CombinedDrafts.create_draft(%{
                 name: "Owner2",
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert {:ok, result} = CombinedDrafts.delete_draft(draft1, mode: :deep)
      assert result.metadata_draft_deleted == false
      assert result.writeup_draft_deleted == false

      assert is_nil(CombinedDrafts.get_draft(draft1.id))
      assert MetadataDrafts.get_draft(md.id) != nil
      assert WriteupDrafts.get_draft(wd.id) != nil
    end

    test "handles nil sub-draft ids gracefully" do
      assert {:ok, draft} = CombinedDrafts.create_draft(%{name: "NoSubs"})

      assert {:ok, result} = CombinedDrafts.delete_draft(draft, mode: :deep)
      assert result.metadata_draft_deleted == false
      assert result.writeup_draft_deleted == false
      assert is_nil(CombinedDrafts.get_draft(draft.id))
    end

    test "preserves preset writeup drafts" do
      {:ok, preset_wd} =
        WriteupDrafts.create_draft(%{name: "Standard Trade Preset", blocks: [], is_preset: true})

      assert {:ok, draft} =
               CombinedDrafts.create_draft(%{
                 name: "WithPreset",
                 writeup_draft_id: preset_wd.id
               })

      assert {:ok, result} = CombinedDrafts.delete_draft(draft, mode: :deep)
      assert result.writeup_draft_deleted == false

      assert is_nil(CombinedDrafts.get_draft(draft.id))
      assert WriteupDrafts.get_draft(preset_wd.id) != nil
    end
  end

  describe "delete_drafts/2 (mode: :shallow)" do
    test "deletes combined drafts by ids, leaving sub-drafts intact" do
      md = create_metadata_draft("Bulk Meta")
      wd = create_writeup_draft("Bulk Writeup")

      assert {:ok, d1} =
               CombinedDrafts.create_draft(%{
                 name: "Bulk1",
                 metadata_draft_id: md.id,
                 writeup_draft_id: wd.id
               })

      assert {:ok, d2} = CombinedDrafts.create_draft(%{name: "Bulk2"})

      assert {:ok, 2} = CombinedDrafts.delete_drafts([d1.id, d2.id], mode: :shallow)

      assert is_nil(CombinedDrafts.get_draft(d1.id))
      assert is_nil(CombinedDrafts.get_draft(d2.id))
      assert MetadataDrafts.get_draft(md.id) != nil
      assert WriteupDrafts.get_draft(wd.id) != nil
    end

    test "default (no opts) behaves as shallow" do
      assert {:ok, d1} = CombinedDrafts.create_draft(%{name: "B1"})
      assert {:ok, d2} = CombinedDrafts.create_draft(%{name: "B2"})

      assert {:ok, 2} = CombinedDrafts.delete_drafts([d1.id, d2.id])
    end

    test "empty list returns zero count" do
      assert {:ok, 0} = CombinedDrafts.delete_drafts([])
    end
  end

  describe "delete_drafts/2 (mode: :deep)" do
    test "deletes combined drafts and orphaned sub-drafts" do
      md1 = create_metadata_draft("Deep Meta 1")
      wd1 = create_writeup_draft("Deep Writeup 1")
      md2 = create_metadata_draft("Deep Meta 2")

      assert {:ok, d1} =
               CombinedDrafts.create_draft(%{
                 name: "Deep1",
                 metadata_draft_id: md1.id,
                 writeup_draft_id: wd1.id
               })

      assert {:ok, d2} =
               CombinedDrafts.create_draft(%{name: "Deep2", metadata_draft_id: md2.id})

      assert {:ok, stats} = CombinedDrafts.delete_drafts([d1.id, d2.id], mode: :deep)
      assert stats.combined_count == 2
      assert stats.metadata_count == 2
      assert stats.writeup_count == 1

      assert is_nil(CombinedDrafts.get_draft(d1.id))
      assert is_nil(CombinedDrafts.get_draft(d2.id))
      assert is_nil(MetadataDrafts.get_draft(md1.id))
      assert is_nil(MetadataDrafts.get_draft(md2.id))
      assert is_nil(WriteupDrafts.get_draft(wd1.id))
    end

    test "preserves sub-drafts still referenced by surviving combined drafts" do
      md = create_metadata_draft("Shared Deep Meta")

      assert {:ok, d1} =
               CombinedDrafts.create_draft(%{name: "DShared1", metadata_draft_id: md.id})

      assert {:ok, _d2} =
               CombinedDrafts.create_draft(%{name: "DShared2", metadata_draft_id: md.id})

      # Only delete d1; d2 still references md
      assert {:ok, stats} = CombinedDrafts.delete_drafts([d1.id], mode: :deep)
      assert stats.metadata_count == 0

      assert MetadataDrafts.get_draft(md.id) != nil
    end

    test "empty list returns zero stats" do
      assert {:ok, %{combined_count: 0, metadata_count: 0, writeup_count: 0}} =
               CombinedDrafts.delete_drafts([], mode: :deep)
    end
  end
end

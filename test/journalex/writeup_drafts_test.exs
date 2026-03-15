defmodule Journalex.WriteupDraftsTest do
  use Journalex.DataCase, async: true

  alias Journalex.WriteupDrafts

  @valid_attrs %{
    name: "Standard Trade",
    blocks: [
      %{"type" => "toggle", "text" => "1min", "children" => []},
      %{"type" => "paragraph", "text" => "Comments:"}
    ]
  }

  describe "create_draft/1" do
    test "creates a draft with valid attrs" do
      assert {:ok, draft} = WriteupDrafts.create_draft(@valid_attrs)
      assert draft.name == "Standard Trade"
      assert length(draft.blocks) == 2
    end

    test "fails without name" do
      assert {:error, changeset} = WriteupDrafts.create_draft(%{blocks: []})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with duplicate name" do
      assert {:ok, _} = WriteupDrafts.create_draft(@valid_attrs)
      assert {:error, changeset} = WriteupDrafts.create_draft(@valid_attrs)
      assert %{name: ["a writeup draft with this name already exists"]} = errors_on(changeset)
    end

    test "name too long is rejected" do
      long_name = String.duplicate("a", 101)
      assert {:error, changeset} = WriteupDrafts.create_draft(%{name: long_name, blocks: []})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "defaults blocks to empty list" do
      assert {:ok, draft} = WriteupDrafts.create_draft(%{name: "Empty"})
      assert draft.blocks == []
    end
  end

  describe "list_drafts/0" do
    test "returns all drafts" do
      assert {:ok, _} = WriteupDrafts.create_draft(%{name: "A", blocks: []})
      assert {:ok, _} = WriteupDrafts.create_draft(%{name: "B", blocks: []})

      drafts = WriteupDrafts.list_drafts()
      assert length(drafts) == 2
    end

    test "returns empty list when no drafts" do
      assert WriteupDrafts.list_drafts() == []
    end
  end

  describe "get_draft!/1" do
    test "returns the draft" do
      assert {:ok, draft} = WriteupDrafts.create_draft(@valid_attrs)
      fetched = WriteupDrafts.get_draft!(draft.id)
      assert fetched.id == draft.id
      assert fetched.name == "Standard Trade"
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        WriteupDrafts.get_draft!(0)
      end
    end
  end

  describe "get_draft/1" do
    test "returns the draft" do
      assert {:ok, draft} = WriteupDrafts.create_draft(@valid_attrs)
      assert %{name: "Standard Trade"} = WriteupDrafts.get_draft(draft.id)
    end

    test "returns nil for non-existent id" do
      assert is_nil(WriteupDrafts.get_draft(0))
    end
  end

  describe "update_draft/2" do
    test "updates name and blocks" do
      assert {:ok, draft} = WriteupDrafts.create_draft(@valid_attrs)

      new_blocks = [%{"type" => "paragraph", "text" => "Updated"}]
      assert {:ok, updated} = WriteupDrafts.update_draft(draft, %{name: "Renamed", blocks: new_blocks})
      assert updated.name == "Renamed"
      assert length(updated.blocks) == 1
    end

    test "fails with invalid attrs" do
      assert {:ok, draft} = WriteupDrafts.create_draft(@valid_attrs)
      assert {:error, changeset} = WriteupDrafts.update_draft(draft, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_draft/1" do
    test "deletes the draft" do
      assert {:ok, draft} = WriteupDrafts.create_draft(@valid_attrs)
      assert {:ok, _} = WriteupDrafts.delete_draft(draft)
      assert is_nil(WriteupDrafts.get_draft(draft.id))
    end
  end

  describe "import_drafts/1" do
    test "imports new drafts" do
      entries = [
        %{"name" => "Draft A", "blocks" => [%{"type" => "paragraph", "text" => "hello"}]},
        %{"name" => "Draft B", "blocks" => []}
      ]

      assert {:ok, %{imported: 2, skipped: 0}} = WriteupDrafts.import_drafts(entries)
      drafts = WriteupDrafts.list_drafts()
      assert length(drafts) == 2
    end

    test "skips existing names" do
      assert {:ok, _} = WriteupDrafts.create_draft(%{name: "Existing", blocks: []})

      entries = [
        %{"name" => "Existing", "blocks" => []},
        %{"name" => "New", "blocks" => []}
      ]

      assert {:ok, %{imported: 1, skipped: 1}} = WriteupDrafts.import_drafts(entries)
      assert length(WriteupDrafts.list_drafts()) == 2
    end

    test "skips entries with is_preset true" do
      entries = [
        %{"name" => "Preset", "blocks" => [], "is_preset" => true},
        %{"name" => "Normal", "blocks" => []}
      ]

      assert {:ok, %{imported: 1, skipped: 1}} = WriteupDrafts.import_drafts(entries)
    end

    test "handles atom-keyed entries" do
      entries = [%{name: "AtomDraft", blocks: []}]
      assert {:ok, %{imported: 1, skipped: 0}} = WriteupDrafts.import_drafts(entries)
    end
  end

  describe "export_all/0" do
    test "exports drafts excluding preset and all preset blocks" do
      WriteupDrafts.ensure_preset_draft()
      assert {:ok, _} = WriteupDrafts.create_draft(%{name: "My Draft", blocks: [%{"type" => "paragraph", "text" => "hi"}]})
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "PB1", blocks: [], group: "G1"})

      result = WriteupDrafts.export_all()

      assert length(result.drafts) == 1
      assert hd(result.drafts).name == "My Draft"
      assert length(result.preset_blocks) == 1
      assert hd(result.preset_blocks).name == "PB1"
      assert hd(result.preset_blocks).group == "G1"
    end

    test "returns empty lists when nothing exists" do
      result = WriteupDrafts.export_all()
      assert result == %{drafts: [], preset_blocks: []}
    end
  end
end

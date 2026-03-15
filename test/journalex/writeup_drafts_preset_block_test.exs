defmodule Journalex.WriteupDrafts.PresetBlockTest do
  use Journalex.DataCase, async: true

  alias Journalex.WriteupDrafts

  @valid_attrs %{
    name: "Timeframes",
    blocks: [
      %{"type" => "toggle", "text" => "1min", "children" => []},
      %{"type" => "toggle", "text" => "5min", "children" => []}
    ]
  }

  @valid_attrs_with_group %{
    name: "Analysis Blocks",
    blocks: [%{"type" => "paragraph", "text" => "Environment Overview:"}],
    group: "Analysis"
  }

  describe "create_preset_block/1" do
    test "creates a preset block with valid attrs" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs)
      assert pb.name == "Timeframes"
      assert length(pb.blocks) == 2
    end

    test "fails without name" do
      assert {:error, changeset} = WriteupDrafts.create_preset_block(%{blocks: []})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with duplicate name" do
      assert {:ok, _} = WriteupDrafts.create_preset_block(@valid_attrs)
      assert {:error, changeset} = WriteupDrafts.create_preset_block(@valid_attrs)
      assert %{name: ["a preset block with this name already exists"]} = errors_on(changeset)
    end

    test "name too long is rejected" do
      long_name = String.duplicate("a", 101)
      assert {:error, changeset} = WriteupDrafts.create_preset_block(%{name: long_name, blocks: []})
      assert %{name: [_msg]} = errors_on(changeset)
    end

    test "defaults blocks to empty list" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(%{name: "Empty"})
      assert pb.blocks == []
    end
  end

  describe "list_preset_blocks/0" do
    test "returns all preset blocks" do
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "A", blocks: []})
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "B", blocks: []})

      pbs = WriteupDrafts.list_preset_blocks()
      assert length(pbs) == 2
    end

    test "returns empty list when none exist" do
      assert WriteupDrafts.list_preset_blocks() == []
    end
  end

  describe "get_preset_block!/1" do
    test "returns the preset block" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs)
      fetched = WriteupDrafts.get_preset_block!(pb.id)
      assert fetched.id == pb.id
      assert fetched.name == "Timeframes"
    end

    test "raises for non-existent id" do
      assert_raise Ecto.NoResultsError, fn ->
        WriteupDrafts.get_preset_block!(0)
      end
    end
  end

  describe "update_preset_block/2" do
    test "updates name and blocks" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs)

      new_blocks = [%{"type" => "paragraph", "text" => "Updated"}]
      assert {:ok, updated} = WriteupDrafts.update_preset_block(pb, %{name: "Renamed", blocks: new_blocks})
      assert updated.name == "Renamed"
      assert length(updated.blocks) == 1
    end

    test "fails with invalid attrs" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs)
      assert {:error, changeset} = WriteupDrafts.update_preset_block(pb, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_preset_block/1" do
    test "deletes the preset block" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs)
      assert {:ok, _} = WriteupDrafts.delete_preset_block(pb)

      assert_raise Ecto.NoResultsError, fn ->
        WriteupDrafts.get_preset_block!(pb.id)
      end
    end
  end

  describe "group field" do
    test "creates a preset block with a group" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs_with_group)
      assert pb.group == "Analysis"
    end

    test "group defaults to nil" do
      assert {:ok, pb} = WriteupDrafts.create_preset_block(@valid_attrs)
      assert pb.group == nil
    end

    test "group too long is rejected" do
      long_group = String.duplicate("a", 101)
      assert {:error, changeset} = WriteupDrafts.create_preset_block(%{name: "X", group: long_group})
      assert %{group: [_msg]} = errors_on(changeset)
    end
  end

  describe "list_preset_block_groups/0" do
    test "returns distinct non-nil group names sorted" do
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "A", group: "Zebra"})
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "B", group: "Alpha"})
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "C", group: "Alpha"})
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "D", group: nil})
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "E"})

      groups = WriteupDrafts.list_preset_block_groups()
      assert groups == ["Alpha", "Zebra"]
    end

    test "returns empty list when no groups" do
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "A"})
      assert WriteupDrafts.list_preset_block_groups() == []
    end
  end

  describe "import_preset_blocks/1" do
    test "imports new preset blocks" do
      entries = [
        %{"name" => "Import1", "blocks" => [%{"type" => "paragraph", "text" => "hello"}], "group" => "G1"},
        %{"name" => "Import2", "blocks" => [], "group" => nil}
      ]

      assert {:ok, %{imported: 2, skipped: 0}} = WriteupDrafts.import_preset_blocks(entries)
      pbs = WriteupDrafts.list_preset_blocks()
      assert length(pbs) == 2
      assert Enum.find(pbs, & &1.name == "Import1").group == "G1"
    end

    test "skips existing names" do
      assert {:ok, _} = WriteupDrafts.create_preset_block(%{name: "Existing"})

      entries = [
        %{"name" => "Existing", "blocks" => []},
        %{"name" => "New", "blocks" => []}
      ]

      assert {:ok, %{imported: 1, skipped: 1}} = WriteupDrafts.import_preset_blocks(entries)
      assert length(WriteupDrafts.list_preset_blocks()) == 2
    end

    test "handles atom-keyed entries" do
      entries = [%{name: "AtomKey", blocks: [], group: "G"}]
      assert {:ok, %{imported: 1, skipped: 0}} = WriteupDrafts.import_preset_blocks(entries)
    end
  end
end

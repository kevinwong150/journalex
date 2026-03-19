defmodule JournalexWeb.BlockHelpersTest do
  use ExUnit.Case, async: true

  alias JournalexWeb.BlockHelpers

  describe "new_block/1" do
    test "creates a paragraph block" do
      block = BlockHelpers.new_block("paragraph")
      assert block == %{"type" => "paragraph", "text" => ""}
    end

    test "creates a toggle block with children" do
      block = BlockHelpers.new_block("toggle")
      assert block == %{"type" => "toggle", "text" => "", "children" => []}
    end

    test "defaults to paragraph for unknown type" do
      block = BlockHelpers.new_block("unknown")
      assert block == %{"type" => "paragraph", "text" => ""}
    end
  end

  describe "add_after/3" do
    test "inserts a block after the given index" do
      blocks = [%{"type" => "paragraph", "text" => "a"}, %{"type" => "paragraph", "text" => "b"}]
      result = BlockHelpers.add_after(blocks, "toggle", 0)
      assert length(result) == 3
      assert Enum.at(result, 1)["type"] == "toggle"
      assert Enum.at(result, 2)["text"] == "b"
    end
  end

  describe "add_end/2" do
    test "appends a block at the end" do
      blocks = [%{"type" => "paragraph", "text" => "a"}]
      result = BlockHelpers.add_end(blocks, "toggle")
      assert length(result) == 2
      assert List.last(result)["type"] == "toggle"
    end

    test "works on empty list" do
      result = BlockHelpers.add_end([], "paragraph")
      assert length(result) == 1
    end
  end

  describe "delete/2" do
    test "removes block at index" do
      blocks = [%{"type" => "paragraph", "text" => "a"}, %{"type" => "toggle", "text" => "b"}]
      result = BlockHelpers.delete(blocks, 0)
      assert length(result) == 1
      assert hd(result)["type"] == "toggle"
    end
  end

  describe "move_up/2" do
    test "swaps block with previous" do
      blocks = [%{"type" => "paragraph", "text" => "a"}, %{"type" => "toggle", "text" => "b"}]
      result = BlockHelpers.move_up(blocks, 1)
      assert Enum.at(result, 0)["text"] == "b"
      assert Enum.at(result, 1)["text"] == "a"
    end

    test "returns unchanged when already first" do
      blocks = [%{"type" => "paragraph", "text" => "a"}, %{"type" => "toggle", "text" => "b"}]
      assert BlockHelpers.move_up(blocks, 0) == blocks
    end
  end

  describe "move_down/2" do
    test "swaps block with next" do
      blocks = [%{"type" => "paragraph", "text" => "a"}, %{"type" => "toggle", "text" => "b"}]
      result = BlockHelpers.move_down(blocks, 0)
      assert Enum.at(result, 0)["text"] == "b"
      assert Enum.at(result, 1)["text"] == "a"
    end

    test "returns unchanged when already last" do
      blocks = [%{"type" => "paragraph", "text" => "a"}, %{"type" => "toggle", "text" => "b"}]
      assert BlockHelpers.move_down(blocks, 1) == blocks
    end
  end

  describe "update_text/3" do
    test "updates text at index" do
      blocks = [%{"type" => "paragraph", "text" => "old"}]
      result = BlockHelpers.update_text(blocks, 0, "new")
      assert hd(result)["text"] == "new"
    end
  end

  describe "toggle_type/2" do
    test "toggles paragraph to toggle" do
      blocks = [%{"type" => "paragraph", "text" => "a"}]
      result = BlockHelpers.toggle_type(blocks, 0)
      assert hd(result)["type"] == "toggle"
      assert hd(result)["children"] == []
    end

    test "toggles toggle to paragraph" do
      blocks = [%{"type" => "toggle", "text" => "a", "children" => []}]
      result = BlockHelpers.toggle_type(blocks, 0)
      assert hd(result)["type"] == "paragraph"
      refute Map.has_key?(hd(result), "children")
    end
  end
end

defmodule Journalex.Notion.BlockBuilderTest do
  use ExUnit.Case, async: true

  alias Journalex.Notion.BlockBuilder

  describe "to_notion_blocks/1" do
    test "converts paragraph block" do
      blocks = [%{"type" => "paragraph", "text" => "Hello world"}]

      assert [
               %{
                 "type" => "paragraph",
                 "paragraph" => %{
                   "rich_text" => [%{"type" => "text", "text" => %{"content" => "Hello world"}}]
                 }
               }
             ] = BlockBuilder.to_notion_blocks(blocks)
    end

    test "converts empty paragraph (blank line)" do
      blocks = [%{"type" => "paragraph", "text" => ""}]

      assert [
               %{
                 "type" => "paragraph",
                 "paragraph" => %{"rich_text" => []}
               }
             ] = BlockBuilder.to_notion_blocks(blocks)
    end

    test "converts paragraph with nil text" do
      blocks = [%{"type" => "paragraph", "text" => nil}]

      assert [
               %{
                 "type" => "paragraph",
                 "paragraph" => %{"rich_text" => []}
               }
             ] = BlockBuilder.to_notion_blocks(blocks)
    end

    test "converts toggle block with children" do
      blocks = [
        %{
          "type" => "toggle",
          "text" => "1min",
          "children" => [%{"type" => "paragraph", "text" => "child text"}]
        }
      ]

      [result] = BlockBuilder.to_notion_blocks(blocks)

      assert result["type"] == "toggle"
      assert result["toggle"]["rich_text"] == [%{"type" => "text", "text" => %{"content" => "1min"}}]

      assert [
               %{
                 "type" => "paragraph",
                 "paragraph" => %{
                   "rich_text" => [%{"type" => "text", "text" => %{"content" => "child text"}}]
                 }
               }
             ] = result["toggle"]["children"]
    end

    test "toggle with empty children gets an empty paragraph child" do
      blocks = [%{"type" => "toggle", "text" => "daily", "children" => []}]

      [result] = BlockBuilder.to_notion_blocks(blocks)

      assert result["type"] == "toggle"
      assert [%{"type" => "paragraph", "paragraph" => %{"rich_text" => []}}] = result["toggle"]["children"]
    end

    test "converts multiple blocks" do
      blocks = [
        %{"type" => "toggle", "text" => "1min", "children" => []},
        %{"type" => "toggle", "text" => "2min", "children" => []},
        %{"type" => "paragraph", "text" => ""},
        %{"type" => "paragraph", "text" => "Environment Overview:"},
        %{"type" => "paragraph", "text" => "Comments:"}
      ]

      result = BlockBuilder.to_notion_blocks(blocks)
      assert length(result) == 5
      assert Enum.at(result, 0)["type"] == "toggle"
      assert Enum.at(result, 1)["type"] == "toggle"
      assert Enum.at(result, 2)["type"] == "paragraph"
      assert Enum.at(result, 3)["type"] == "paragraph"
      assert Enum.at(result, 4)["type"] == "paragraph"
    end

    test "returns empty list for nil input" do
      assert BlockBuilder.to_notion_blocks(nil) == []
    end

    test "returns empty list for empty list" do
      assert BlockBuilder.to_notion_blocks([]) == []
    end

    test "unknown block type becomes empty paragraph" do
      blocks = [%{"type" => "heading", "text" => "Title"}]

      assert [%{"type" => "paragraph", "paragraph" => %{"rich_text" => []}}] =
               BlockBuilder.to_notion_blocks(blocks)
    end
  end
end

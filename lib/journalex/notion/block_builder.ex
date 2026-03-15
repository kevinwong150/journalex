defmodule Journalex.Notion.BlockBuilder do
  @moduledoc """
  Converts internal writeup block format to Notion API block format.

  Internal format (stored in DB):
    [%{"type" => "paragraph", "text" => "Some text"},
     %{"type" => "toggle", "text" => "Toggle title", "children" => [%{"type" => "paragraph", "text" => "Child"}]}]

  Notion API format:
    [%{"type" => "paragraph", "paragraph" => %{"rich_text" => [%{"type" => "text", "text" => %{"content" => "Some text"}}]}},
     %{"type" => "toggle", "toggle" => %{"rich_text" => [...], "children" => [...]}}]
  """

  @doc """
  Converts a list of internal block maps to Notion API block format.
  """
  @spec to_notion_blocks(list(map())) :: list(map())
  def to_notion_blocks(blocks) when is_list(blocks) do
    Enum.map(blocks, &to_notion_block/1)
  end

  def to_notion_blocks(_), do: []

  defp to_notion_block(%{"type" => "paragraph"} = block) do
    %{
      "type" => "paragraph",
      "paragraph" => %{
        "rich_text" => rich_text(block["text"])
      }
    }
  end

  defp to_notion_block(%{"type" => "toggle"} = block) do
    children =
      (block["children"] || [])
      |> Enum.map(&to_notion_block/1)

    # If toggle has no children, add an empty paragraph (Notion requires at least one child)
    children = if children == [], do: [empty_paragraph()], else: children

    %{
      "type" => "toggle",
      "toggle" => %{
        "rich_text" => rich_text(block["text"]),
        "children" => children
      }
    }
  end

  # Fallback: treat unknown types as empty paragraphs
  defp to_notion_block(_block), do: empty_paragraph()

  defp rich_text(nil), do: []
  defp rich_text(""), do: []

  defp rich_text(text) when is_binary(text) do
    [%{"type" => "text", "text" => %{"content" => text}}]
  end

  defp rich_text(_), do: []

  defp empty_paragraph do
    %{
      "type" => "paragraph",
      "paragraph" => %{
        "rich_text" => []
      }
    }
  end
end

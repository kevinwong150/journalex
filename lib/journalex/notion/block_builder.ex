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

  @doc """
  Converts a list of Notion API block maps to internal writeup block format.

  Only `paragraph` and `toggle` types are mapped. Other block types are skipped.
  For toggle blocks, children are expected to be pre-fetched and present under
  `["toggle"]["children"]` before calling this function.

  ## Examples

      iex> BlockBuilder.from_notion_blocks([
      ...>   %{"type" => "paragraph", "paragraph" => %{"rich_text" => [%{"type" => "text", "text" => %{"content" => "Hello"}}]}}
      ...> ])
      [%{"type" => "paragraph", "text" => "Hello"}]
  """
  @spec from_notion_blocks(list(map())) :: list(map())
  def from_notion_blocks(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&from_notion_block/1)
    |> Enum.reject(&is_nil/1)
  end

  def from_notion_blocks(_), do: []

  defp from_notion_block(%{"type" => "paragraph"} = block) do
    text = extract_rich_text(get_in(block, ["paragraph", "rich_text"]) || [])
    %{"type" => "paragraph", "text" => text}
  end

  defp from_notion_block(%{"type" => "toggle"} = block) do
    text = extract_rich_text(get_in(block, ["toggle", "rich_text"]) || [])
    children_raw = get_in(block, ["toggle", "children"]) || []
    children = from_notion_blocks(children_raw)
    %{"type" => "toggle", "text" => text, "children" => children}
  end

  # Skip unsupported block types (headings, bullets, dividers, etc.)
  defp from_notion_block(_), do: nil

  defp extract_rich_text(rich_text) when is_list(rich_text) do
    rich_text
    |> Enum.map(fn rt -> get_in(rt, ["text", "content"]) || "" end)
    |> Enum.join("")
  end

  defp extract_rich_text(_), do: ""

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

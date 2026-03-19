defmodule JournalexWeb.BlockHelpers do
  @moduledoc """
  Pure functions for manipulating writeup block lists.

  Each function takes a block list (and arguments) and returns a new block list.
  Used by WriteupDraftLive and TradeDraftLive to avoid duplicating block manipulation logic.
  """

  @doc """
  Creates a new block map of the given type.
  """
  def new_block("toggle"), do: %{"type" => "toggle", "text" => "", "children" => []}
  def new_block(_), do: %{"type" => "paragraph", "text" => ""}

  @doc """
  Inserts a new block of `type` after the given index.
  """
  def add_after(blocks, type, after_idx) do
    List.insert_at(blocks, after_idx + 1, new_block(type))
  end

  @doc """
  Appends a new block of `type` at the end.
  """
  def add_end(blocks, type) do
    blocks ++ [new_block(type)]
  end

  @doc """
  Deletes the block at the given index.
  """
  def delete(blocks, idx) do
    List.delete_at(blocks, idx)
  end

  @doc """
  Moves the block at `idx` one position up (toward index 0).
  Returns the list unchanged if already at the top.
  """
  def move_up(blocks, idx) when idx > 0, do: swap(blocks, idx, idx - 1)
  def move_up(blocks, _idx), do: blocks

  @doc """
  Moves the block at `idx` one position down.
  Returns the list unchanged if already at the bottom.
  """
  def move_down(blocks, idx) when idx < length(blocks) - 1, do: swap(blocks, idx, idx + 1)
  def move_down(blocks, _idx), do: blocks

  @doc """
  Updates the text of the block at `idx`.
  """
  def update_text(blocks, idx, value) do
    List.update_at(blocks, idx, &Map.put(&1, "text", value))
  end

  @doc """
  Toggles the block at `idx` between paragraph and toggle types.
  """
  def toggle_type(blocks, idx) do
    List.update_at(blocks, idx, fn block ->
      case block["type"] do
        "paragraph" -> block |> Map.put("type", "toggle") |> Map.put_new("children", [])
        "toggle" -> block |> Map.put("type", "paragraph") |> Map.delete("children")
        _ -> block
      end
    end)
  end

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)

    list
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end
end

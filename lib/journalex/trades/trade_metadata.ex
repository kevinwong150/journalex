defmodule Journalex.Trades.TradeMetadata do
  @moduledoc """
  Alias for backwards compatibility.
  Use Journalex.Trades.Metadata.V2 directly for new code.
  """

  defdelegate changeset(metadata, attrs), to: Journalex.Trades.Metadata.V2
  defdelegate new(attrs \\ %{}), to: Journalex.Trades.Metadata.V2

  # This module is now just an alias - the actual schema is in Metadata.V2
  defmacro __using__(_opts) do
    quote do
      alias Journalex.Trades.Metadata.V2, as: TradeMetadata
    end
  end
end

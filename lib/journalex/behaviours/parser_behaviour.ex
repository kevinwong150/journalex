defmodule Journalex.ParserBehaviour do
  @moduledoc """
  Behaviour for the ActivityStatementParser, enabling Mox-based testing.
  """

  @callback parse_trades_file(String.t()) :: [map()]
  @callback parse_period_file(String.t()) :: String.t() | nil
end

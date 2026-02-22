defmodule Journalex.TradesBehaviour do
  @moduledoc """
  Behaviour for the Trades context, enabling Mox-based testing.
  Only includes functions called by the upload-result LiveView.
  """

  @callback upsert_trade_rows(list()) :: {non_neg_integer(), nil | list()}
  @callback build_action_chain(map(), keyword()) :: map() | nil
  @callback persisted_trade_keys(Date.t(), Date.t(), list()) :: MapSet.t()
end

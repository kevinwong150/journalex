defmodule Journalex.Trades.PreflightChecks do
  @moduledoc """
  Pure, stateless module that runs pre-flight checks on a list of trades
  before Notion write operations (push, bulk push, insert missing).

  Returns a list of issue maps; an empty list means all checks passed.

  Issue shape:
    %{trade_label: String.t(), field: String.t(), message: String.t(), check_name: atom()}

  Context shape (passed at call time — no process state):
    %{ticker_id_cache: map(), date_id_cache: map()}
  """

  @checks [
    %{name: :win_empty_size,          fun: &__MODULE__.check_win_empty_size/2,       versions: [2],  operations: :all},
    %{name: :missing_ticker_relation, fun: &__MODULE__.check_missing_ticker/2,       versions: :all, operations: :all},
    %{name: :missing_date_relation,   fun: &__MODULE__.check_missing_date/2,         versions: :all, operations: :all},
    %{name: :cache_not_loaded,        fun: &__MODULE__.check_cache_not_loaded/2,     versions: :all, operations: :all}
  ]

  @doc """
  Run all applicable checks against the given `trades` list.

  `operation` is an atom like `:push_bound`, `:bulk_push`, or `:insert_missing`.
  `ctx` is a map: `%{ticker_id_cache: map(), date_id_cache: map()}`.

  Returns a (possibly empty) list of issue maps.
  """
  @spec run([map()], atom(), map()) :: [map()]
  def run(trades, operation, ctx) when is_list(trades) do
    trades
    |> Enum.flat_map(fn trade ->
      @checks
      |> Enum.filter(fn check ->
        version_matches?(check.versions, trade.metadata_version) and
          operation_matches?(check.operations, operation)
      end)
      |> Enum.flat_map(fn check -> check.fun.(trade, ctx) end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Check implementations (public so the module attribute captures work)
  # ---------------------------------------------------------------------------

  def check_win_empty_size(trade, _ctx) do
    metadata = trade.metadata || %{}
    size = Map.get(metadata, "size", Map.get(metadata, :size))

    if trade.result == "WIN" and size_empty?(size) do
      [issue(trade, "size", "WIN trade has no position size set", :win_empty_size)]
    else
      []
    end
  end

  def check_missing_ticker(trade, ctx) do
    ticker = trade.ticker || trade.symbol
    if is_binary(ticker) and not Map.has_key?(ctx.ticker_id_cache, ticker) and not caches_empty?(ctx) do
      [issue(trade, "ticker", "No Ticker Details page for #{ticker}", :missing_ticker_relation)]
    else
      []
    end
  end

  def check_missing_date(trade, ctx) do
    date_key = trade_date_key(trade)
    if is_binary(date_key) and not Map.has_key?(ctx.date_id_cache, date_key) and not caches_empty?(ctx) do
      [issue(trade, "date", "No Market Daily page for #{date_key}", :missing_date_relation)]
    else
      []
    end
  end

  def check_cache_not_loaded(_trade, ctx) do
    if caches_empty?(ctx) do
      [%{trade_label: nil, field: "cache", message: "Relation caches are unavailable — retry the operation to reload them", check_name: :cache_not_loaded}]
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp version_matches?(:all, _version), do: true
  defp version_matches?(versions, version) when is_list(versions), do: version in versions

  defp operation_matches?(:all, _operation), do: true
  defp operation_matches?(operations, operation) when is_list(operations), do: operation in operations

  defp issue(trade, field, message, check_name) do
    %{
      trade_label: trade_label(trade),
      field: field,
      message: message,
      check_name: check_name
    }
  end

  defp trade_label(trade) do
    ticker = Map.get(trade, :ticker) || Map.get(trade, :symbol)
    dt = Map.get(trade, :datetime)
    iso = if is_struct(dt, DateTime), do: DateTime.to_iso8601(dt), else: nil
    if is_binary(ticker) and is_binary(iso), do: ticker <> "@" <> iso, else: inspect(trade)
  end

  defp trade_date_key(%{datetime: %DateTime{} = dt}) do
    dt |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp trade_date_key(_), do: nil

  defp caches_empty?(%{ticker_id_cache: t, date_id_cache: d}) do
    map_size(t) == 0 and map_size(d) == 0
  end

  defp size_empty?(nil), do: true
  defp size_empty?(""), do: true
  defp size_empty?(0), do: true
  defp size_empty?("0"), do: true
  defp size_empty?(%Decimal{} = d), do: Decimal.compare(d, Decimal.new(0)) == :eq
  defp size_empty?(_), do: false
end

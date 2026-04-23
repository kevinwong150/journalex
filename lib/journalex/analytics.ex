defmodule Journalex.Analytics do
  @moduledoc """
  Analytics context for trading performance analysis.

  All functions accept an `opts` keyword list:
    - `:versions` — list of integers; defaults to all distinct metadata_version values in DB
    - `:from` — `Date` lower bound (inclusive); default nil (no lower bound)
    - `:to` — `Date` upper bound (inclusive); default nil (no upper bound)
    - `:r_size` — float; defaults to `Settings.get_r_size()`

  The `done? = true` filter is ALWAYS applied — analytics only count completed trades.
  """

  @behaviour Journalex.AnalyticsBehaviour

  import Ecto.Query

  alias Journalex.{Repo, Settings}
  alias Journalex.Trades.Trade

  # ---------------------------------------------------------------------------
  # Available versions
  # ---------------------------------------------------------------------------

  @impl true
  def available_versions do
    Repo.all(
      from t in Trade,
        where: not is_nil(t.metadata_version),
        distinct: true,
        select: t.metadata_version,
        order_by: [asc: t.metadata_version]
    )
  end

  # ---------------------------------------------------------------------------
  # Base query
  # ---------------------------------------------------------------------------

  defp base_query(opts) do
    versions = Keyword.get(opts, :versions, available_versions())
    from_date = Keyword.get(opts, :from)
    to_date = Keyword.get(opts, :to)

    query =
      from t in Trade,
        where: fragment("(?->>?)::boolean = true", t.metadata, "done?"),
        where: t.metadata_version in ^versions

    query = if from_date, do: where(query, [t], fragment("?::date", t.datetime) >= ^from_date), else: query
    query = if to_date, do: where(query, [t], fragment("?::date", t.datetime) <= ^to_date), else: query
    query
  end

  defp to_r(decimal, r_size) when r_size > 0 do
    Float.round(Decimal.to_float(decimal) / r_size, 3)
  end

  defp to_r(_decimal, _r_size), do: 0.0

  # ---------------------------------------------------------------------------
  # KPI summary
  # ---------------------------------------------------------------------------

  @impl true
  def kpi_summary(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())
    trades = Repo.all(from t in base_query(opts), select: {t.result, t.realized_pl})

    r_values = Enum.map(trades, fn {_result, pl} -> to_r(pl, r_size) end)
    wins = Enum.filter(trades, fn {result, _} -> result == "WIN" end)
    losses = Enum.filter(trades, fn {result, _} -> result == "LOSE" end)

    trade_count = length(trades)
    win_count = length(wins)

    win_r_values = Enum.map(wins, fn {_, pl} -> to_r(pl, r_size) end)
    loss_r_values = Enum.map(losses, fn {_, pl} -> to_r(pl, r_size) end)

    avg_win = safe_avg(win_r_values)
    avg_loss = safe_avg(loss_r_values) |> abs()
    win_rate = if trade_count > 0, do: win_count / trade_count, else: 0.0

    profit_factor =
      if avg_loss > 0 and win_count > 0 do
        Float.round(avg_win * win_count / (avg_loss * (trade_count - win_count)), 3)
      else
        0.0
      end

    expectancy = Float.round(win_rate * avg_win - (1 - win_rate) * avg_loss, 3)

    %{
      total_r: Float.round(Enum.sum(r_values), 3),
      win_rate: Float.round(win_rate, 4),
      trade_count: trade_count,
      avg_r: Float.round(safe_avg(r_values), 3),
      best_r: Float.round(Enum.max(r_values, fn -> 0.0 end), 3),
      worst_r: Float.round(Enum.min(r_values, fn -> 0.0 end), 3),
      profit_factor: profit_factor,
      expectancy: expectancy
    }
  end

  # ---------------------------------------------------------------------------
  # Equity curve
  # ---------------------------------------------------------------------------

  @impl true
  def equity_curve(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    trades =
      Repo.all(
        from t in base_query(opts),
          select: {fragment("?::date", t.datetime), t.realized_pl},
          order_by: [asc: t.datetime]
      )

    trades
    |> Enum.reduce({[], 0.0}, fn {date, pl}, {acc, cumulative} ->
      r = to_r(pl, r_size)
      new_cum = Float.round(cumulative + r, 3)
      {[{date, new_cum} | acc], new_cum}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # ---------------------------------------------------------------------------
  # Calendar heatmap
  # ---------------------------------------------------------------------------

  @impl true
  def calendar_heatmap(year, opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    from_date = Date.new!(year, 1, 1)
    to_date = Date.new!(year, 12, 31)
    merged_opts = opts |> Keyword.put(:from, from_date) |> Keyword.put(:to, to_date)

    Repo.all(
      from t in base_query(merged_opts),
        group_by: fragment("?::date", t.datetime),
        select: {fragment("?::date", t.datetime), sum(t.realized_pl)},
        order_by: [asc: fragment("?::date", t.datetime)]
    )
    |> Enum.map(fn {date, pl} ->
      date_str = Date.to_iso8601(date)
      {date_str, to_r(pl, r_size)}
    end)
  end

  # ---------------------------------------------------------------------------
  # R/R analysis
  # ---------------------------------------------------------------------------

  @impl true
  def rr_analysis(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    # Only V2 trades have initial_risk_reward_ratio
    v2_opts =
      opts
      |> Keyword.update(:versions, [2], fn vs -> Enum.filter(vs, &(&1 >= 2)) end)

    trades =
      Repo.all(
        from t in base_query(v2_opts),
          where: not is_nil(fragment("?->>'initial_risk_reward_ratio'", t.metadata)),
          select: {
            t.result,
            t.realized_pl,
            fragment("(?->>'initial_risk_reward_ratio')::float", t.metadata)
          }
      )

    r_values = Enum.map(trades, fn {_, pl, _} -> to_r(pl, r_size) end)
    wins = Enum.filter(trades, fn {result, _, _} -> result == "WIN" end)
    losses = Enum.filter(trades, fn {result, _, _} -> result == "LOSE" end)

    win_r = Enum.map(wins, fn {_, pl, _} -> to_r(pl, r_size) end)
    loss_r = Enum.map(losses, fn {_, pl, _} -> to_r(pl, r_size) end) |> Enum.map(&abs/1)
    avg_win = safe_avg(win_r)
    avg_loss = safe_avg(loss_r)
    trade_count = length(trades)
    win_rate = if trade_count > 0, do: length(wins) / trade_count, else: 0.0
    expectancy = Float.round(win_rate * avg_win - (1 - win_rate) * avg_loss, 3)

    # Histogram bins: -3 to +3 in 0.5 increments
    bins = build_histogram_bins(r_values, -3.0, 3.0, 0.5)

    # Fulfillment: WIN trades where realized_r >= initial_rr
    fulfilled =
      Enum.count(wins, fn {_, pl, initial_rr} ->
        to_r(pl, r_size) >= (initial_rr || 0)
      end)

    fulfillment_rate =
      if length(wins) > 0, do: Float.round(fulfilled / length(wins), 4), else: 0.0

    scatter_data =
      Enum.map(trades, fn {result, pl, initial_rr} ->
        %{x: initial_rr || 0.0, y: to_r(pl, r_size), result: result}
      end)

    %{
      histogram_bins: bins,
      scatter_data: scatter_data,
      expectancy: expectancy,
      fulfillment_rate: fulfillment_rate
    }
  end

  # ---------------------------------------------------------------------------
  # Breakdown by dimension
  # ---------------------------------------------------------------------------

  @impl true
  def breakdown_by_dimension(dimension, opts \\ []) do
    # TODO: implement — select group key from JSONB, aggregate R per group
    _ = {dimension, opts}
    []
  end

  # ---------------------------------------------------------------------------
  # Long vs short
  # ---------------------------------------------------------------------------

  @impl true
  def long_vs_short(opts \\ []) do
    # TODO: implement — split on aggregated_side, compute KPIs per side
    _ = opts
    %{long: %{}, short: %{}}
  end

  # ---------------------------------------------------------------------------
  # Flags impact
  # ---------------------------------------------------------------------------

  @impl true
  def flags_impact(opts \\ []) do
    # TODO: implement — for each boolean flag, compute avg_r when ON vs OFF
    _ = opts
    []
  end

  # ---------------------------------------------------------------------------
  # Time heatmap
  # ---------------------------------------------------------------------------

  @impl true
  def time_heatmap(dimension, opts \\ []) do
    # TODO: implement — group by timeslot x weekday, compute avg R
    _ = {dimension, opts}
    []
  end

  # ---------------------------------------------------------------------------
  # Day of week breakdown
  # ---------------------------------------------------------------------------

  @impl true
  def day_of_week_breakdown(opts \\ []) do
    # TODO: implement — group by day of week, compute total R + win/loss counts
    _ = opts
    []
  end

  # ---------------------------------------------------------------------------
  # Monthly breakdown
  # ---------------------------------------------------------------------------

  @impl true
  def monthly_breakdown(opts \\ []) do
    # TODO: implement — group by year-month, compute totals
    _ = opts
    []
  end

  # ---------------------------------------------------------------------------
  # Scorecard periods
  # ---------------------------------------------------------------------------

  @impl true
  def scorecard_periods(unit, opts \\ []) do
    # TODO: implement — group by week or month, build scorecard rows
    _ = {unit, opts}
    []
  end

  # ---------------------------------------------------------------------------
  # Streak data
  # ---------------------------------------------------------------------------

  @impl true
  def streak_data(opts \\ []) do
    # TODO: implement — scan trade sequence in date order, compute streaks
    _ = opts
    %{
      current_streak: 0,
      max_win_streak: 0,
      max_loss_streak: 0,
      per_trade_sequence: []
    }
  end

  # ---------------------------------------------------------------------------
  # Ticker summary
  # ---------------------------------------------------------------------------

  @impl true
  def ticker_summary(opts \\ []) do
    # TODO: implement — group by ticker, compute per-ticker KPIs
    _ = opts
    []
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp safe_avg([]), do: 0.0
  defp safe_avg(values), do: Float.round(Enum.sum(values) / length(values), 3)

  defp build_histogram_bins(values, min_val, max_val, step) do
    step_count = round((max_val - min_val) / step)

    bins =
      for i <- 0..(step_count - 1) do
        bin_start = Float.round(min_val + i * step, 2)
        bin_end = Float.round(bin_start + step, 2)
        count = Enum.count(values, fn v -> v >= bin_start and v < bin_end end)
        %{bin: "#{bin_start}~#{bin_end}", count: count}
      end

    # Catch values outside the range
    below = Enum.count(values, &(&1 < min_val))
    above = Enum.count(values, &(&1 >= max_val))

    [%{bin: "<#{min_val}", count: below}] ++
      bins ++
      [%{bin: "≥#{max_val}", count: above}]
  end
end

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

  @v1_flags ~w(revenge_trade? fomo? operation_mistake? follow_setup? follow_stop_loss_management? unnecessary_trade?)
  @v2_flags ~w(revenge_trade? fomo? operation_mistake? add_size? adjusted_risk_reward? align_with_trend? better_risk_reward_ratio? big_picture? earning_report? follow_up_trial? good_lesson? hot_sector? momentum? news? normal_emotion? overnight? overnight_in_purpose? slipped_position? choppychart? close_trade_remorse? no_luck? no_risk? clear_liquidity_grab? entry_after_liquidity_grab? instant_lose? too_tight_stop_loss? affected_by_other_trade? mid_range? fully_wrong_direction?)
  @all_flags Enum.uniq(@v1_flags ++ @v2_flags)
  @weekday_names ~w(Sun Mon Tue Wed Thu Fri Sat)

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
    field = dimension_field(dimension)
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          where: not is_nil(fragment("?->>?", t.metadata, ^field)),
          select: {fragment("?->>?", t.metadata, ^field), t.result, t.realized_pl}
      )

    rows
    |> Enum.reject(fn {label, _, _} -> label == "" end)
    |> Enum.group_by(fn {label, _, _} -> label end)
    |> Enum.map(fn {label, group} ->
      count = length(group)
      wins = Enum.count(group, fn {_, result, _} -> result == "WIN" end)
      r_values = Enum.map(group, fn {_, _, pl} -> to_r(pl, r_size) end)
      total_r = r_values |> Enum.sum() |> Float.round(3)
      win_rate = if count > 0, do: Float.round(wins / count, 4), else: 0.0
      {label, total_r, win_rate, count}
    end)
    |> Enum.sort_by(fn {_, total_r, _, _} -> -total_r end)
  end

  defp dimension_field(:rank), do: "rank"
  defp dimension_field(:setup), do: "setup"
  defp dimension_field(:sector), do: "sector"
  defp dimension_field(:close_trigger), do: "close_trigger"
  defp dimension_field(:cap_size), do: "cap_size"
  defp dimension_field(:order_type), do: "order_type"

  # ---------------------------------------------------------------------------
  # Long vs short
  # ---------------------------------------------------------------------------

  @impl true
  def long_vs_short(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          select: {t.aggregated_side, t.result, t.realized_pl}
      )

    compute_side_kpis = fn side_rows ->
      count = length(side_rows)
      wins = Enum.count(side_rows, fn {_, result, _} -> result == "WIN" end)
      r_values = Enum.map(side_rows, fn {_, _, pl} -> to_r(pl, r_size) end)
      %{
        count: count,
        win_rate: if(count > 0, do: Float.round(wins / count, 4), else: 0.0),
        total_r: r_values |> Enum.sum() |> Float.round(3),
        avg_r: safe_avg(r_values)
      }
    end

    longs = Enum.filter(rows, fn {side, _, _} -> side == "LONG" end)
    shorts = Enum.filter(rows, fn {side, _, _} -> side == "SHORT" end)

    %{long: compute_side_kpis.(longs), short: compute_side_kpis.(shorts)}
  end

  # ---------------------------------------------------------------------------
  # Flags impact
  # ---------------------------------------------------------------------------

  @impl true
  def flags_impact(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          select: {t.metadata_version, t.result, t.realized_pl, t.metadata}
      )

    versions_present = rows |> Enum.map(fn {v, _, _, _} -> v end) |> Enum.uniq()

    flags =
      versions_present
      |> Enum.flat_map(fn
        1 -> @v1_flags
        _ -> @v2_flags
      end)
      |> Enum.uniq()

    Enum.map(flags, fn flag ->
      {on_rows, off_rows} =
        Enum.split_with(rows, fn {_, _, _, meta} ->
          is_map(meta) and Map.get(meta, flag) == true
        end)

      on_r = Enum.map(on_rows, fn {_, _, pl, _} -> to_r(pl, r_size) end)
      off_r = Enum.map(off_rows, fn {_, _, pl, _} -> to_r(pl, r_size) end)
      {flag, safe_avg(on_r), safe_avg(off_r), length(on_rows), length(off_rows)}
    end)
    |> Enum.sort_by(fn {_, _, _, count_on, _} -> -count_on end)
  end

  # ---------------------------------------------------------------------------
  # Time heatmap
  # ---------------------------------------------------------------------------

  @impl true
  def time_heatmap(dimension, opts \\ []) do
    field =
      case dimension do
        :entry_timeslot -> "entry_timeslot"
        :close_timeslot -> "close_timeslot"
      end

    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          where: not is_nil(fragment("?->>?", t.metadata, ^field)),
          select: {
            fragment("?->>?", t.metadata, ^field),
            fragment("EXTRACT(DOW FROM ?)::integer", t.datetime),
            t.realized_pl
          }
      )

    rows
    |> Enum.reject(fn {ts, _, _} -> ts == "" end)
    |> Enum.group_by(fn {ts, dow, _} -> {ts, dow} end)
    |> Enum.map(fn {{ts, dow}, group} ->
      avg_r = group |> Enum.map(fn {_, _, pl} -> to_r(pl, r_size) end) |> safe_avg()
      {ts, dow_to_name(dow), avg_r}
    end)
  end

  defp dow_to_name(dow), do: Enum.at(@weekday_names, dow)

  # ---------------------------------------------------------------------------
  # Day of week breakdown
  # ---------------------------------------------------------------------------

  @impl true
  def day_of_week_breakdown(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          select: {
            fragment("EXTRACT(DOW FROM ?)::integer", t.datetime),
            t.result,
            t.realized_pl
          }
      )

    rows
    |> Enum.group_by(fn {dow, _, _} -> dow end)
    |> Enum.map(fn {dow, group} ->
      count = length(group)
      wins = Enum.count(group, fn {_, r, _} -> r == "WIN" end)
      total_r = group |> Enum.map(fn {_, _, pl} -> to_r(pl, r_size) end) |> Enum.sum() |> Float.round(3)
      {dow_to_name(dow), total_r, wins, count - wins}
    end)
    |> Enum.sort_by(fn {name, _, _, _} ->
      Enum.find_index(@weekday_names, &(&1 == name)) || 99
    end)
  end

  # ---------------------------------------------------------------------------
  # Monthly breakdown
  # ---------------------------------------------------------------------------

  @impl true
  def monthly_breakdown(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          select: {
            fragment("to_char(?, 'YYYY-MM')", t.datetime),
            t.result,
            t.realized_pl
          }
      )

    rows
    |> Enum.group_by(fn {month, _, _} -> month end)
    |> Enum.map(fn {month, group} ->
      count = length(group)
      wins = Enum.count(group, fn {_, r, _} -> r == "WIN" end)
      total_r = group |> Enum.map(fn {_, _, pl} -> to_r(pl, r_size) end) |> Enum.sum() |> Float.round(3)
      {month, total_r, wins, count - wins}
    end)
    |> Enum.sort_by(fn {month, _, _, _} -> month end)
  end

  # ---------------------------------------------------------------------------
  # Scorecard periods
  # ---------------------------------------------------------------------------

  @impl true
  def scorecard_periods(unit, opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    period_format =
      case unit do
        :week -> "IYYY-IW"
        :month -> "YYYY-MM"
      end

    rows =
      Repo.all(
        from t in base_query(opts),
          select: {
            fragment("to_char(?, ?)", t.datetime, ^period_format),
            t.result,
            t.realized_pl,
            fragment("?->>'rank'", t.metadata),
            t.metadata
          }
      )

    rows
    |> Enum.group_by(fn {period, _, _, _, _} -> period end)
    |> Enum.map(fn {period, group} ->
      count = length(group)
      wins = Enum.count(group, fn {_, r, _, _, _} -> r == "WIN" end)
      r_values = Enum.map(group, fn {_, _, pl, _, _} -> to_r(pl, r_size) end)
      total_r = r_values |> Enum.sum() |> Float.round(3)
      avg_r = safe_avg(r_values)
      win_pct = if count > 0, do: Float.round(wins / count, 4), else: 0.0
      top_rank = most_common(Enum.map(group, fn {_, _, _, rank, _} -> rank end))
      top_flag = most_frequent_flag(Enum.map(group, fn {_, _, _, _, meta} -> meta end))

      %{
        period: period,
        count: count,
        win_pct: win_pct,
        total_r: total_r,
        avg_r: avg_r,
        top_rank: top_rank,
        top_flag: top_flag
      }
    end)
    |> Enum.sort_by(& &1.period)
  end

  defp most_common(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_, freq} -> freq end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp most_frequent_flag(metas) do
    metas
    |> Enum.flat_map(fn meta ->
      if is_map(meta) do
        Enum.filter(@all_flags, fn flag -> Map.get(meta, flag) == true end)
      else
        []
      end
    end)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_, freq} -> freq end, fn -> {nil, 0} end)
    |> elem(0)
  end

  # ---------------------------------------------------------------------------
  # Streak data
  # ---------------------------------------------------------------------------

  @impl true
  def streak_data(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    trades =
      Repo.all(
        from t in base_query(opts),
          select: {t.result, t.realized_pl},
          order_by: [asc: t.datetime]
      )

    sequence = Enum.map(trades, fn {result, pl} -> {result, to_r(pl, r_size)} end)
    current_streak = compute_current_streak(sequence)
    {max_win_streak, max_loss_streak} = compute_max_streaks(sequence)

    %{
      current_streak: current_streak,
      max_win_streak: max_win_streak,
      max_loss_streak: max_loss_streak,
      per_trade_sequence: sequence
    }
  end

  defp compute_current_streak([]), do: 0

  defp compute_current_streak(sequence) do
    {last_result, _} = List.last(sequence)

    count =
      sequence
      |> Enum.reverse()
      |> Enum.take_while(fn {r, _} -> r == last_result end)
      |> length()

    if last_result == "WIN", do: count, else: -count
  end

  defp compute_max_streaks(sequence) do
    {max_win, max_loss, _, _} =
      Enum.reduce(sequence, {0, 0, 0, 0}, fn {result, _}, {mw, ml, cw, cl} ->
        if result == "WIN" do
          new_cw = cw + 1
          {max(mw, new_cw), ml, new_cw, 0}
        else
          new_cl = cl + 1
          {mw, max(ml, new_cl), 0, new_cl}
        end
      end)

    {max_win, max_loss}
  end

  # ---------------------------------------------------------------------------
  # Ticker summary
  # ---------------------------------------------------------------------------

  @impl true
  def ticker_summary(opts \\ []) do
    r_size = Keyword.get(opts, :r_size, Settings.get_r_size())

    rows =
      Repo.all(
        from t in base_query(opts),
          select: {t.ticker, t.result, t.realized_pl, fragment("?::date", t.datetime)},
          order_by: [asc: t.datetime]
      )

    rows
    |> Enum.group_by(fn {ticker, _, _, _} -> ticker end)
    |> Enum.map(fn {ticker, group} ->
      count = length(group)
      wins = Enum.count(group, fn {_, result, _, _} -> result == "WIN" end)
      r_values = Enum.map(group, fn {_, _, pl, _} -> to_r(pl, r_size) end)
      total_r = r_values |> Enum.sum() |> Float.round(3)
      avg_r = safe_avg(r_values)
      win_rate = if count > 0, do: Float.round(wins / count, 4), else: 0.0
      last_date = group |> Enum.map(fn {_, _, _, d} -> d end) |> Enum.max_by(&Date.to_iso8601/1)
      {ticker, count, win_rate, total_r, avg_r, last_date}
    end)
    |> Enum.sort_by(fn {_, _, _, total_r, _, _} -> -total_r end)
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

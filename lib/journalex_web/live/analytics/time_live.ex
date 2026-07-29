defmodule JournalexWeb.Analytics.TimeLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}
  alias JournalexWeb.Analytics.PeriodHelpers
  import JournalexWeb.AnalyticsFilterBar
  import JournalexWeb.ChartComponent
  import JournalexWeb.InfoTooltip

  @weekdays ~w(Mon Tue Wed Thu Fri)

  @impl true
  def mount(_params, _session, socket) do
    versions_available = Analytics.available_versions()
    r_mode = Settings.get_analytics_r_mode()
    has_v2 = Enum.any?(versions_available, &(&1 >= 2))
    exception_days = Settings.get_analytics_exception_days()

    socket =
      assign(socket,
        versions_available: versions_available,
        selected_versions: versions_available,
        from: nil,
        to: nil,
        r_mode: r_mode,
        exception_days: exception_days,
        exclude_exception_days?: true,
        has_v2: has_v2,
        entry_option: build_timeslot_heatmap_option([]),
        close_option: build_timeslot_heatmap_option([]),
        dow_option: build_dow_option([]),
        monthly_option: build_monthly_option([]),
        entry_breakdown_option: build_timeslot_breakdown_option([]),
        close_breakdown_option: build_timeslot_breakdown_option([]),
        duration_option: build_duration_band_option([])
      )

    {:ok, if(connected?(socket), do: reload(socket, []), else: socket)}
  end

  @impl true
  def handle_event("toggle_version", %{"version" => v_str}, socket) do
    v = String.to_integer(v_str)
    selected = socket.assigns.selected_versions
    new_selected = if v in selected, do: Enum.reject(selected, &(&1 == v)), else: Enum.sort([v | selected])
    {:noreply, reload(socket, selected_versions: new_selected)}
  end

  @impl true
  def handle_event("set_period", %{"period" => period}, socket) when period != "" do
    {from, to} = PeriodHelpers.period_to_dates(period)
    {:noreply, reload(socket, from: from, to: to)}
  end

  def handle_event("set_period", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter_dates", %{"from" => from, "to" => to}, socket) do
    {:noreply, reload(socket, from: from, to: to)}
  end

  @impl true
  def handle_event("set_r_mode", %{"mode" => mode}, socket) when mode in ["r", "usd", "both"] do
    Settings.set_analytics_r_mode(mode)
    {:noreply, reload(socket, r_mode: mode)}
  end

  @impl true
  def handle_event("toggle_exception_days", _params, socket) do
    {:noreply, reload(socket, exclude_exception_days?: !socket.assigns.exclude_exception_days?)}
  end

  @impl true
  def handle_event("reload", _params, socket) do
    {:noreply, reload(socket, [])}
  end

  defp reload(socket, changes) do
    socket = assign(socket, changes)
    socket = assign(socket, exception_days: Settings.get_analytics_exception_days())
    a = socket.assigns
    has_v2 = Enum.any?(a.selected_versions, &(&1 >= 2))
    socket = assign(socket, has_v2: has_v2)
    opts = build_opts(a.selected_versions, a.from, a.to, a.exclude_exception_days?)
    start_async(socket, :load_charts, fn -> compute_chart_data(opts) end)
  end

  defp compute_chart_data(opts) do
    v2_opts = Keyword.update(opts, :versions, [], fn vs -> Enum.filter(vs, &(&1 >= 2)) end)
    {
      Analytics.time_heatmap(:entry_timeslot, opts),
      Analytics.time_heatmap(:close_timeslot, v2_opts),
      Analytics.day_of_week_breakdown(opts),
      Analytics.monthly_breakdown(opts),
      Analytics.timeslot_breakdown(:entry_timeslot, opts),
      Analytics.timeslot_breakdown(:close_timeslot, v2_opts),
      Analytics.duration_band_breakdown(opts)
    }
  end

  @impl true
  def handle_async(:load_charts, {:ok, {entry_heatmap, close_heatmap, dow, monthly, entry_breakdown, close_breakdown, duration_breakdown}}, socket) do
    entry_option = build_timeslot_heatmap_option(entry_heatmap)
    close_option = build_timeslot_heatmap_option(close_heatmap)
    dow_option = build_dow_option(dow)
    monthly_option = build_monthly_option(monthly)
    entry_breakdown_option = build_timeslot_breakdown_option(entry_breakdown)
    close_breakdown_option = build_timeslot_breakdown_option(close_breakdown)
    duration_option = build_duration_band_option(duration_breakdown)

    socket =
      assign(socket,
        entry_option: entry_option,
        close_option: close_option,
        dow_option: dow_option,
        monthly_option: monthly_option,
        entry_breakdown_option: entry_breakdown_option,
        close_breakdown_option: close_breakdown_option,
        duration_option: duration_option
      )
      |> push_event("chart-update", %{id: "entry-timeslot-heatmap", option: entry_option})
      |> push_event("chart-update", %{id: "close-timeslot-heatmap", option: close_option})
      |> push_event("chart-update", %{id: "dow-chart", option: dow_option})
      |> push_event("chart-update", %{id: "monthly-chart", option: monthly_option})
      |> push_event("chart-update", %{id: "entry-timeslot-perf", option: entry_breakdown_option})
      |> push_event("chart-update", %{id: "close-timeslot-perf", option: close_breakdown_option})
      |> push_event("chart-update", %{id: "duration-band-chart", option: duration_option})

    {:noreply, socket}
  end

  @impl true
  def handle_async(:load_charts, {:exit, _reason}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to load chart data.")}
  end

  defp build_opts(versions, from, to, exclude_exception_days?) do
    opts = [versions: versions]
    opts = if d = parse_date(from), do: Keyword.put(opts, :from, d), else: opts
    opts = if d = parse_date(to), do: Keyword.put(opts, :to, d), else: opts
    Keyword.put(opts, :exclude_exception_days, exclude_exception_days?)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp build_timeslot_heatmap_option([]) do
    %{
      tooltipFormatter: "timeslot_heatmap_stats",
      tooltip: %{trigger: "item", confine: true},
      grid: %{left: 70, right: 20, top: 40, bottom: 62},
      xAxis: %{
        type: "category",
        data: [],
        splitArea: %{show: true},
        axisLabel: %{rotate: 0, interval: 0, lineHeight: 12, fontSize: 10}
      },
      yAxis: %{type: "category", data: @weekdays, splitArea: %{show: true}},
      visualMap: %{
        min: -1,
        max: 1,
        calculable: false,
        orient: "horizontal",
        left: "center",
        top: 5,
        itemWidth: 12,
        itemHeight: 60,
        inRange: %{color: ["#ef4444", "#f5f5f5", "#22c55e"]}
      },
      series: [%{type: "heatmap", data: [], label: %{show: false}}]
    }
  end

  defp build_timeslot_heatmap_option(data) do
    timeslots = data |> Enum.map(fn {ts, _, _, _} -> ts end) |> Enum.uniq() |> Enum.sort()
    weekdays = @weekdays
    axis_timeslots = Enum.map(timeslots, &format_timeslot_axis_label/1)

    ts_index = timeslots |> Enum.with_index() |> Map.new()
    wd_index = weekdays |> Enum.with_index() |> Map.new()

    heatmap_data =
      Enum.flat_map(data, fn {ts, wd, avg_r, count} ->
        xi = Map.get(ts_index, ts)
        yi = Map.get(wd_index, wd)

        if xi && yi do
          [
            %{
              value: [xi, yi, Float.round(avg_r, 2)],
              timeslot: ts,
              weekday: wd,
              count: count
            }
          ]
        else
          []
        end
      end)

    r_values = Enum.map(data, fn {_, _, r, _} -> r end)
    max_abs = Enum.map(r_values, &abs/1) |> Enum.max(fn -> 1.0 end)

    %{
      tooltipFormatter: "timeslot_heatmap_stats",
      tooltip: %{
        trigger: "item",
        confine: true
      },
      grid: %{left: 70, right: 20, top: 40, bottom: 62},
      xAxis: %{
        type: "category",
        data: axis_timeslots,
        splitArea: %{show: true},
        axisLabel: %{rotate: 0, interval: 0, lineHeight: 12, fontSize: 10}
      },
      yAxis: %{type: "category", data: weekdays, splitArea: %{show: true}},
      visualMap: %{
        min: -max_abs,
        max: max_abs,
        calculable: false,
        orient: "horizontal",
        left: "center",
        top: 5,
        itemWidth: 12,
        itemHeight: 60,
        inRange: %{color: ["#ef4444", "#f5f5f5", "#22c55e"]}
      },
      series: [%{
        type: "heatmap",
        data: heatmap_data,
        label: %{show: false}
      }]
    }
  end

  defp format_timeslot_axis_label(timeslot) when is_binary(timeslot) do
    case String.split(timeslot, "-", parts: 2) do
      [start_time, end_time] -> format_hhmm(start_time) <> "\n" <> format_hhmm(end_time)
      _ -> timeslot
    end
  end

  defp format_hhmm(<<h1, h2, m1, m2>>) do
    <<h1, h2, ?:, m1, m2>>
  end

  defp format_hhmm(value), do: value

  defp build_timeslot_breakdown_option([]) do
    %{
      tooltipFormatter: "timeslot_breakdown",
      tooltip: %{trigger: "axis", confine: true},
      legend: %{data: ["Total R", "Avg R"], top: 0},
      grid: %{left: 55, right: 55, top: 30, bottom: 62},
      xAxis: %{
        type: "category",
        data: [],
        axisLabel: %{interval: 0, lineHeight: 12, fontSize: 10}
      },
      yAxis: [
        %{type: "value", name: "Total R", position: "left", nameTextStyle: %{align: "right"}},
        %{type: "value", name: "Avg R", position: "right", nameTextStyle: %{align: "left"}}
      ],
      series: [
        %{name: "Total R", type: "bar", data: [], yAxisIndex: 0},
        %{
          name: "Avg R",
          type: "line",
          data: [],
          yAxisIndex: 1,
          symbol: "circle",
          symbolSize: 5,
          lineStyle: %{color: "#3b82f6", width: 2},
          itemStyle: %{color: "#3b82f6"}
        }
      ]
    }
  end

  defp build_timeslot_breakdown_option(data) do
    labels = Enum.map(data, fn {ts, _, _, _, _} -> format_timeslot_axis_label(ts) end)

    bar_data =
      Enum.map(data, fn {ts, total_r, _avg_r, wins, losses} ->
        color = if total_r >= 0, do: "#22c55e", else: "#ef4444"
        %{value: Float.round(total_r, 2), itemStyle: %{color: color}, timeslot: ts, wins: wins, losses: losses}
      end)

    line_data =
      Enum.map(data, fn {ts, _total_r, avg_r, wins, losses} ->
        %{value: Float.round(avg_r, 2), timeslot: ts, wins: wins, losses: losses}
      end)

    %{
      tooltipFormatter: "timeslot_breakdown",
      tooltip: %{trigger: "axis", confine: true},
      legend: %{data: ["Total R", "Avg R"], top: 0},
      grid: %{left: 55, right: 55, top: 30, bottom: 62},
      xAxis: %{
        type: "category",
        data: labels,
        axisLabel: %{interval: 0, lineHeight: 12, fontSize: 10}
      },
      yAxis: [
        %{type: "value", name: "Total R", position: "left", nameTextStyle: %{align: "right"}},
        %{type: "value", name: "Avg R", position: "right", nameTextStyle: %{align: "left"}}
      ],
      series: [
        %{
          name: "Total R",
          type: "bar",
          data: bar_data,
          yAxisIndex: 0
        },
        %{
          name: "Avg R",
          type: "line",
          data: line_data,
          yAxisIndex: 1,
          symbol: "circle",
          symbolSize: 5,
          lineStyle: %{color: "#3b82f6", width: 2},
          itemStyle: %{color: "#3b82f6"}
        }
      ]
    }
  end

  defp build_duration_band_option([]) do
    %{
      tooltipFormatter: "duration_band",
      tooltip: %{trigger: "axis", confine: true},
      legend: %{data: ["Total R", "Win Rate %"], top: 0},
      grid: %{left: 55, right: 60, top: 30, bottom: 40},
      xAxis: %{type: "category", data: []},
      yAxis: [
        %{type: "value", name: "Total R", position: "left", nameTextStyle: %{align: "right"}},
        %{type: "value", name: "Win Rate %", position: "right", min: 0, max: 100, nameTextStyle: %{align: "left"}}
      ],
      series: [
        %{name: "Total R", type: "bar", data: [], yAxisIndex: 0},
        %{
          name: "Win Rate %",
          type: "line",
          data: [],
          yAxisIndex: 1,
          symbol: "circle",
          symbolSize: 5,
          lineStyle: %{color: "#3b82f6", width: 2},
          itemStyle: %{color: "#3b82f6"}
        }
      ]
    }
  end

  defp build_duration_band_option(data) do
    labels = Enum.map(data, fn {label, _, _, _, _, _} -> label end)

    bar_data =
      Enum.map(data, fn {_label, total_r, avg_r, _win_rate, wins, losses} ->
        color = if total_r >= 0, do: "#22c55e", else: "#ef4444"
        %{value: Float.round(total_r, 2), itemStyle: %{color: color}, wins: wins, losses: losses, avg_r: Float.round(avg_r, 2)}
      end)

    line_data =
      Enum.map(data, fn {_label, _total_r, _avg_r, win_rate, _wins, _losses} ->
        Float.round(win_rate * 100, 1)
      end)

    %{
      tooltipFormatter: "duration_band",
      tooltip: %{trigger: "axis", confine: true},
      legend: %{data: ["Total R", "Win Rate %"], top: 0},
      grid: %{left: 55, right: 60, top: 30, bottom: 40},
      xAxis: %{type: "category", data: labels},
      yAxis: [
        %{type: "value", name: "Total R", position: "left", nameTextStyle: %{align: "right"}},
        %{type: "value", name: "Win Rate %", position: "right", min: 0, max: 100, nameTextStyle: %{align: "left"}}
      ],
      series: [
        %{
          name: "Total R",
          type: "bar",
          data: bar_data,
          yAxisIndex: 0
        },
        %{
          name: "Win Rate %",
          type: "line",
          data: line_data,
          yAxisIndex: 1,
          symbol: "circle",
          symbolSize: 5,
          lineStyle: %{color: "#3b82f6", width: 2},
          itemStyle: %{color: "#3b82f6"}
        }
      ]
    }
  end

  defp build_dow_option([]) do
    %{
      tooltip: %{trigger: "axis"},
      grid: %{left: 50, right: 20, top: 10, bottom: 30},
      xAxis: %{type: "category", data: []},
      yAxis: %{type: "value", name: "Total R"},
      series: [%{type: "bar", data: []}]
    }
  end

  defp build_dow_option(data) do
    trading_days = Enum.filter(data, fn {name, _, _, _} -> name in @weekdays end)
    labels = Enum.map(trading_days, fn {name, _, _, _} -> name end)
    r_values = Enum.map(trading_days, fn {_, r, _, _} -> r end)

    bar_data =
      Enum.map(r_values, fn r ->
        color = if r >= 0, do: "#22c55e", else: "#ef4444"
        %{value: r, itemStyle: %{color: color}}
      end)

    %{
      tooltip: %{trigger: "axis"},
      grid: %{left: 50, right: 20, top: 10, bottom: 30},
      xAxis: %{type: "category", data: labels},
      yAxis: %{type: "value", name: "Total R"},
      series: [%{type: "bar", data: bar_data}]
    }
  end

  defp build_monthly_option([]) do
    %{
      tooltip: %{trigger: "axis"},
      grid: %{left: 50, right: 20, top: 10, bottom: 40},
      xAxis: %{type: "category", data: [], axisLabel: %{rotate: 45}},
      yAxis: %{type: "value", name: "Total R"},
      series: [%{type: "bar", data: []}]
    }
  end

  defp build_monthly_option(data) do
    labels = Enum.map(data, fn {month, _, _, _} -> month end)
    r_values = Enum.map(data, fn {_, r, _, _} -> r end)

    bar_data =
      Enum.map(r_values, fn r ->
        color = if r >= 0, do: "#22c55e", else: "#ef4444"
        %{value: r, itemStyle: %{color: color}}
      end)

    %{
      tooltip: %{trigger: "axis"},
      grid: %{left: 50, right: 20, top: 10, bottom: 40},
      xAxis: %{type: "category", data: labels, axisLabel: %{rotate: 45}},
      yAxis: %{type: "value", name: "Total R"},
      series: [%{type: "bar", data: bar_data}]
    }
  end
end

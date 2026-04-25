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

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: nil,
       to: nil,
       r_mode: r_mode,
       has_v2: has_v2
     )
     |> reload([])}
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
  def handle_event("reload", _params, socket) do
    {:noreply, reload(socket, [])}
  end

  defp reload(socket, changes) do
    socket = assign(socket, changes)
    a = socket.assigns
    opts = build_opts(a.selected_versions, a.from, a.to)

    entry_heatmap = Analytics.time_heatmap(:entry_timeslot, opts)
    dow = Analytics.day_of_week_breakdown(opts)
    monthly = Analytics.monthly_breakdown(opts)

    v2_opts = Keyword.update(opts, :versions, [], fn vs -> Enum.filter(vs, &(&1 >= 2)) end)
    close_heatmap = Analytics.time_heatmap(:close_timeslot, v2_opts)

    entry_option = build_timeslot_heatmap_option(entry_heatmap)
    close_option = build_timeslot_heatmap_option(close_heatmap)
    dow_option = build_dow_option(dow)
    monthly_option = build_monthly_option(monthly)

    socket
    |> assign(
      entry_heatmap: entry_heatmap,
      close_heatmap: close_heatmap,
      dow: dow,
      monthly: monthly,
      entry_option: entry_option,
      close_option: close_option,
      dow_option: dow_option,
      monthly_option: monthly_option
    )
    |> push_event("chart-update", %{id: "entry-timeslot-heatmap", option: entry_option})
    |> push_event("chart-update", %{id: "close-timeslot-heatmap", option: close_option})
    |> push_event("chart-update", %{id: "dow-chart", option: dow_option})
    |> push_event("chart-update", %{id: "monthly-chart", option: monthly_option})
  end

  defp build_opts(versions, from, to) do
    opts = [versions: versions]
    opts = if d = parse_date(from), do: Keyword.put(opts, :from, d), else: opts
    if d = parse_date(to), do: Keyword.put(opts, :to, d), else: opts
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
    %{series: [%{type: "heatmap", data: []}]}
  end

  defp build_timeslot_heatmap_option(data) do
    timeslots = data |> Enum.map(fn {ts, _, _} -> ts end) |> Enum.uniq() |> Enum.sort()
    weekdays = @weekdays

    ts_index = timeslots |> Enum.with_index() |> Map.new()
    wd_index = weekdays |> Enum.with_index() |> Map.new()

    heatmap_data =
      Enum.flat_map(data, fn {ts, wd, avg_r} ->
        xi = Map.get(ts_index, ts)
        yi = Map.get(wd_index, wd)
        if xi && yi, do: [[xi, yi, avg_r]], else: []
      end)

    r_values = Enum.map(data, fn {_, _, r} -> r end)
    max_abs = Enum.map(r_values, &abs/1) |> Enum.max(fn -> 1.0 end)

    %{
      tooltip: %{trigger: "item"},
      grid: %{left: 70, right: 20, top: 10, bottom: 60},
      xAxis: %{type: "category", data: timeslots, splitArea: %{show: true}, axisLabel: %{rotate: 45}},
      yAxis: %{type: "category", data: weekdays, splitArea: %{show: true}},
      visualMap: %{
        min: -max_abs,
        max: max_abs,
        calculable: true,
        orient: "horizontal",
        left: "center",
        bottom: 0,
        inRange: %{color: ["#ef4444", "#f5f5f5", "#22c55e"]}
      },
      series: [%{type: "heatmap", data: heatmap_data, label: %{show: true, formatter: "{c}"}}]
    }
  end

  defp build_dow_option([]) do
    %{series: [%{type: "bar", data: []}]}
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
    %{series: [%{type: "bar", data: []}]}
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

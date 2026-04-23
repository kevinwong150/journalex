defmodule JournalexWeb.Analytics.CalendarLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}
  alias JournalexWeb.Analytics.PeriodHelpers
  import JournalexWeb.AnalyticsFilterBar
  import JournalexWeb.ChartComponent
  import JournalexWeb.InfoTooltip

  @impl true
  def mount(_params, _session, socket) do
    versions_available = Analytics.available_versions()
    year = Date.utc_today().year

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: nil,
       to: nil,
       r_mode: Settings.get_analytics_r_mode(),
       year: year,
       heatmap_data: Analytics.calendar_heatmap(year, versions: versions_available),
       calendar_option: %{}
     )
     |> build_calendar_option()}
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
    data = Analytics.calendar_heatmap(a.year, versions: a.selected_versions)
    socket = socket |> assign(heatmap_data: data) |> build_calendar_option()
    push_event(socket, "chart-update", %{id: "calendar-heatmap", option: socket.assigns.calendar_option})
  end

  defp build_calendar_option(socket) do
    a = socket.assigns
    year = a.year

    # Monday of the week containing Jan 1 (may be in Dec of previous year)
    first_day = Date.new!(year, 1, 1)
    last_day = Date.new!(year, 12, 31)
    today = Date.utc_today()
    range_end = if Date.compare(last_day, today) == :gt, do: today, else: last_day

    first_monday = Date.add(first_day, -(Date.day_of_week(first_day) - 1))

    weeks =
      Stream.iterate(first_monday, &Date.add(&1, 7))
      |> Enum.take_while(&(Date.compare(&1, last_day) != :gt))

    week_labels = Enum.map(weeks, &Calendar.strftime(&1, "%b %d"))

    week_index_map =
      weeks
      |> Enum.with_index()
      |> Map.new(fn {d, i} -> {Date.to_iso8601(d), i} end)

    weekday_names = ["Mon", "Tue", "Wed", "Thu", "Fri"]

    # Build lookup map from heatmap data
    trade_map = Map.new(a.heatmap_data)

    # All Mon–Fri cells up to today — used to mark no-trade days
    weekday_cells =
      Date.range(first_day, range_end)
      |> Enum.filter(&(Date.day_of_week(&1) in 1..5))
      |> Enum.map(fn date ->
        dow = Date.day_of_week(date)
        week_start = Date.add(date, -(dow - 1))
        week_idx = Map.get(week_index_map, Date.to_iso8601(week_start))
        wd_idx = dow - 1
        r_value = Map.get(trade_map, Date.to_iso8601(date))
        {week_idx, wd_idx, r_value}
      end)
      |> Enum.reject(fn {week_idx, _, _} -> week_idx == nil end)

    trade_data = for {wi, di, r} <- weekday_cells, r != nil, do: [wi, di, r]

    no_trade_data =
      for {wi, di, nil} <- weekday_cells do
        %{
          value: [wi, di, 0],
          itemStyle: %{
            decal: %{
              color: "rgba(0,0,0,0.2)",
              dashArrayX: [[1, 4]],
              dashArrayY: [1, 4],
              rotation: 0.7854
            }
          }
        }
      end

    option = %{
      aria: %{enabled: true},
      tooltip: %{trigger: "item"},
      grid: %{top: 20, bottom: 90, left: 50, right: 20},
      xAxis: %{
        type: "category",
        data: week_labels,
        splitArea: %{show: true},
        axisLabel: %{rotate: 90, interval: 3, fontSize: 10}
      },
      yAxis: %{
        type: "category",
        data: weekday_names,
        splitArea: %{show: true}
      },
      visualMap: [
        %{
          seriesIndex: 0,
          min: -0.5,
          max: 0.5,
          show: false,
          inRange: %{color: ["#e5e7eb"]}
        },
        %{
          seriesIndex: 1,
          min: -3,
          max: 3,
          calculable: true,
          orient: "horizontal",
          left: "center",
          bottom: 10,
          inRange: %{color: ["#ef4444", "#f5f5f5", "#22c55e"]}
        }
      ],
      series: [
        %{
          name: "no_trade",
          type: "heatmap",
          data: no_trade_data,
          label: %{show: false},
          silent: true
        },
        %{
          name: "trades",
          type: "heatmap",
          data: trade_data,
          label: %{show: false},
          emphasis: %{itemStyle: %{shadowBlur: 10, shadowColor: "rgba(0,0,0,0.5)"}}
        }
      ]
    }

    assign(socket, calendar_option: option)
  end
end

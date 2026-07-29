defmodule JournalexWeb.Analytics.CompareLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}
  import JournalexWeb.AnalyticsFilterBar
  import JournalexWeb.ChartComponent

  @impl true
  def mount(_params, _session, socket) do
    versions_available = Analytics.available_versions()
    r_mode = Settings.get_analytics_r_mode()
    exception_days = Settings.get_analytics_exception_days()
    today = Date.utc_today()

    # Default: Period A = last 30 days, Period B = 30 days before that
    to_a = Date.to_iso8601(today)
    from_a = Date.to_iso8601(Date.add(today, -30))
    to_b = Date.to_iso8601(Date.add(today, -31))
    from_b = Date.to_iso8601(Date.add(today, -61))

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       r_mode: r_mode,
       from_a: from_a,
       to_a: to_a,
       from_b: from_b,
       to_b: to_b,
       exception_days: exception_days,
       exclude_exception_days?: true
     )
     |> reload([])}
  end

  @impl true
  def handle_event("filter_a", %{"from" => from, "to" => to}, socket) do
    {:noreply, reload(socket, from_a: from, to_a: to)}
  end

  @impl true
  def handle_event("filter_b", %{"from" => from, "to" => to}, socket) do
    {:noreply, reload(socket, from_b: from, to_b: to)}
  end

  @impl true
  def handle_event("toggle_version", %{"version" => v_str}, socket) do
    v = String.to_integer(v_str)
    selected = socket.assigns.selected_versions
    new_selected = if v in selected, do: Enum.reject(selected, &(&1 == v)), else: Enum.sort([v | selected])
    {:noreply, reload(socket, selected_versions: new_selected)}
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

    opts_a = build_opts(a.selected_versions, a.from_a, a.to_a, a.exclude_exception_days?)
    opts_b = build_opts(a.selected_versions, a.from_b, a.to_b, a.exclude_exception_days?)

    kpis_a = Analytics.kpi_summary(opts_a)
    kpis_b = Analytics.kpi_summary(opts_b)
    equity_a = Analytics.equity_curve(opts_a)
    equity_b = Analytics.equity_curve(opts_b)

    compare_option = build_compare_option(equity_a, equity_b)

    socket
    |> assign(kpis_a: kpis_a, kpis_b: kpis_b, compare_option: compare_option)
    |> push_event("chart-update", %{id: "compare-equity", option: compare_option})
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

  # Re-zero both equity curves to start at 0 for visual comparison
  defp build_compare_option(equity_a, equity_b) do
    base_a = if equity_a != [], do: elem(hd(equity_a), 1), else: 0.0
    base_b = if equity_b != [], do: elem(hd(equity_b), 1), else: 0.0

    make_series = fn equity, base, name, color ->
      data = Enum.map(equity, fn {_, cum_r} -> Float.round(cum_r - base, 3) end)
      indices = Enum.with_index(equity) |> Enum.map(fn {_, i} -> i + 1 end)
      {indices, data, name, color}
    end

    {idx_a, data_a, _, _} = make_series.(equity_a, base_a, "Period A", "#3b82f6")
    {idx_b, data_b, _, _} = make_series.(equity_b, base_b, "Period B", "#f59e0b")

    # Use the longer index list as x-axis
    x_data = if length(idx_a) >= length(idx_b), do: idx_a, else: idx_b

    %{
      tooltip: %{trigger: "axis"},
      legend: %{data: ["Period A", "Period B"]},
      xAxis: %{type: "category", data: x_data, boundaryGap: false},
      yAxis: %{type: "value", name: "R (re-zeroed)"},
      grid: %{left: 50, right: 20, top: 30, bottom: 40},
      series: [
        %{name: "Period A", type: "line", data: data_a, smooth: true, lineStyle: %{color: "#3b82f6"}, itemStyle: %{color: "#3b82f6"}},
        %{name: "Period B", type: "line", data: data_b, smooth: true, lineStyle: %{color: "#f59e0b"}, itemStyle: %{color: "#f59e0b"}}
      ]
    }
  end

  defp kpi_delta(a, b) when is_number(a) and is_number(b) do
    diff = Float.round(a * 1.0 - b * 1.0, 3)
    cond do
      diff > 0 -> {:up, "+#{diff}"}
      diff < 0 -> {:down, "#{diff}"}
      true -> {nil, "±0"}
    end
  end

  defp kpi_delta(_, _), do: {nil, ""}
end

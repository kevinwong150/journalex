defmodule JournalexWeb.Analytics.EquityLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}
  alias JournalexWeb.Analytics.PeriodHelpers
  import JournalexWeb.AnalyticsFilterBar
  import JournalexWeb.ChartComponent
  import JournalexWeb.InfoTooltip
  import JournalexWeb.KpiCard

  @impl true
  def mount(_params, _session, socket) do
    versions_available = Analytics.available_versions()
    r_mode = Settings.get_analytics_r_mode()
    exception_days = Settings.get_analytics_exception_days()

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: nil,
       to: nil,
       r_mode: r_mode,
       exception_days: exception_days,
       exclude_exception_days?: true
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
    opts = build_opts(a.selected_versions, a.from, a.to, a.exclude_exception_days?)
    equity = Analytics.equity_curve(opts)
    streak = Analytics.streak_data(opts)
    equity_option = build_equity_option(equity)
    max_dd = max_drawdown(equity)

    socket
    |> assign(
      equity: equity,
      streak: streak,
      equity_option: equity_option,
      max_drawdown: max_dd
    )
    |> push_event("chart-update", %{id: "equity-curve", option: equity_option})
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

  defp build_equity_option(equity) do
    dates = Enum.map(equity, fn {d, _} -> Date.to_iso8601(d) end)
    values = Enum.map(equity, fn {_, r} -> r end)

    %{
      tooltip: %{trigger: "axis"},
      xAxis: %{type: "category", data: dates, boundaryGap: false},
      yAxis: %{type: "value", name: "Cumulative R"},
      grid: %{left: 50, right: 20, top: 20, bottom: 40},
      series: [
        %{
          name: "Equity",
          type: "line",
          data: values,
          smooth: true,
          areaStyle: %{opacity: 0.3},
          lineStyle: %{color: "#22c55e"},
          itemStyle: %{color: "#22c55e"}
        }
      ]
    }
  end

  defp max_drawdown([]), do: 0.0

  defp max_drawdown(equity) do
    equity
    |> Enum.reduce({0.0, 0.0}, fn {_, cum_r}, {peak, max_dd} ->
      new_peak = max(peak, cum_r)
      dd = Float.round(new_peak - cum_r, 3)
      {new_peak, max(max_dd, dd)}
    end)
    |> elem(1)
  end

  defp streak_label(n) when n > 0, do: "+#{n}W"
  defp streak_label(n) when n < 0, do: "#{abs(n)}L"
  defp streak_label(0), do: "\u2014"
end

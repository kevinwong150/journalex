defmodule JournalexWeb.Analytics.DashboardLive do
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
    today = Date.utc_today()
    from_date = Date.new!(today.year, 1, 1) |> Date.to_iso8601()
    to_date = Date.to_iso8601(today)

    opts = build_opts(versions_available, from_date, to_date, r_mode)
    kpis = Analytics.kpi_summary(opts)
    equity = Analytics.equity_curve(opts)

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: from_date,
       to: to_date,
       r_mode: r_mode,
       kpis: kpis,
       equity_option: build_equity_option(equity)
     )}
  end

  @impl true
  def handle_event("toggle_version", %{"version" => v_str}, socket) do
    v = String.to_integer(v_str)
    selected = socket.assigns.selected_versions

    new_selected =
      if v in selected,
        do: Enum.reject(selected, &(&1 == v)),
        else: Enum.sort([v | selected])

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
    opts = build_opts(a.selected_versions, a.from, a.to, a.r_mode)
    kpis = Analytics.kpi_summary(opts)
    equity = Analytics.equity_curve(opts)
    equity_option = build_equity_option(equity)

    socket
    |> assign(kpis: kpis, equity_option: equity_option)
    |> push_event("chart-update", %{id: "dashboard-equity", option: equity_option})
  end

  defp build_opts(versions, from, to, _r_mode) do
    opts = [versions: versions]
    opts = if d = parse_date(from), do: Keyword.put(opts, :from, d), else: opts
    opts = if d = parse_date(to), do: Keyword.put(opts, :to, d), else: opts
    opts
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
      series: [
        %{
          name: "Equity",
          type: "line",
          data: values,
          smooth: true,
          areaStyle: %{}
        }
      ]
    }
  end
end

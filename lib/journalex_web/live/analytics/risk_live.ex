defmodule JournalexWeb.Analytics.RiskLive do
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
    opts = [versions: Enum.filter(versions_available, &(&1 >= 2))]
    rr = Analytics.rr_analysis(opts)

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: nil,
       to: nil,
       r_mode: r_mode,
       rr: rr,
       histogram_option: build_histogram_option(rr),
       scatter_option: build_scatter_option(rr)
     )}
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
    v2_versions = Enum.filter(a.selected_versions, &(&1 >= 2))
    opts = build_opts(v2_versions, a.from, a.to)
    rr = Analytics.rr_analysis(opts)
    histogram_option = build_histogram_option(rr)
    scatter_option = build_scatter_option(rr)

    socket
    |> assign(rr: rr, histogram_option: histogram_option, scatter_option: scatter_option)
    |> push_event("chart-update", %{id: "rr-histogram", option: histogram_option})
    |> push_event("chart-update", %{id: "rr-scatter", option: scatter_option})
  end

  defp build_opts(versions, from, to) do
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

  defp build_histogram_option(%{histogram_bins: bins}) do
    %{
      tooltip: %{trigger: "axis"},
      xAxis: %{type: "category", data: Enum.map(bins, & &1.bin)},
      yAxis: %{type: "value", name: "Count"},
      series: [%{type: "bar", data: Enum.map(bins, & &1.count)}]
    }
  end

  defp build_scatter_option(%{scatter_data: data}) do
    win_data = data |> Enum.filter(&(&1.result == "WIN")) |> Enum.map(&[&1.x, &1.y])
    loss_data = data |> Enum.filter(&(&1.result == "LOSE")) |> Enum.map(&[&1.x, &1.y])

    %{
      tooltip: %{trigger: "item"},
      xAxis: %{type: "value", name: "Initial R:R"},
      yAxis: %{type: "value", name: "Realized R"},
      series: [
        %{name: "WIN", type: "scatter", data: win_data, itemStyle: %{color: "#22c55e"}},
        %{name: "LOSE", type: "scatter", data: loss_data, itemStyle: %{color: "#ef4444"}}
      ]
    }
  end
end

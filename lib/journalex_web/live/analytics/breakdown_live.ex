defmodule JournalexWeb.Analytics.BreakdownLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}
  alias JournalexWeb.Analytics.PeriodHelpers
  import JournalexWeb.AnalyticsFilterBar
  import JournalexWeb.ChartComponent

  @tabs [:rank, :setup, :sector, :close_trigger, :cap_size, :patterns, :regular_lessons, :long_vs_short]

  @impl true
  def mount(_params, _session, socket) do
    versions_available = Analytics.available_versions()
    r_mode = Settings.get_analytics_r_mode()

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: nil,
       to: nil,
       r_mode: r_mode,
       active_tab: :rank
     )
     |> reload([])}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    {:noreply, reload(socket, active_tab: tab_atom)}
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

    {breakdown, ls} =
      case a.active_tab do
        :long_vs_short ->
          {[], Analytics.long_vs_short(opts)}

        tab when tab in [:patterns, :regular_lessons] ->
          {Analytics.multi_select_breakdown(tab, opts), %{long: %{}, short: %{}}}

        _ ->
          {Analytics.breakdown_by_dimension(a.active_tab, opts), %{long: %{}, short: %{}}}
      end

    chart_option = if a.active_tab == :long_vs_short, do: %{}, else: build_chart(breakdown)

    socket
    |> assign(breakdown: breakdown, long_vs_short: ls, breakdown_option: chart_option)
    |> push_event("chart-update", %{id: "breakdown-chart", option: chart_option})
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

  defp build_chart([]) do
    %{series: [%{type: "bar", data: []}]}
  end

  defp build_chart(data) do
    labels = Enum.map(data, fn {label, _, _, _} -> label end)
    r_values = Enum.map(data, fn {_, r, _, _} -> r end)

    bar_data =
      Enum.map(r_values, fn r ->
        color = if r >= 0, do: "#22c55e", else: "#ef4444"
        %{value: r, itemStyle: %{color: color}}
      end)

    %{
      tooltip: %{trigger: "axis"},
      grid: %{left: 130, right: 20, top: 10, bottom: 30},
      xAxis: %{type: "value", name: "Total R"},
      yAxis: %{type: "category", data: Enum.reverse(labels)},
      series: [%{type: "bar", data: Enum.reverse(bar_data)}]
    }
  end

  defp tab_label(:rank), do: "Rank"
  defp tab_label(:setup), do: "Setup"
  defp tab_label(:sector), do: "Sector"
  defp tab_label(:close_trigger), do: "Close Trigger"
  defp tab_label(:cap_size), do: "Cap Size"
  defp tab_label(:patterns), do: "Patterns"
  defp tab_label(:regular_lessons), do: "Regular Lessons"
  defp tab_label(:long_vs_short), do: "Long vs Short"

  defp tabs, do: @tabs
end

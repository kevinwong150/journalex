defmodule JournalexWeb.Analytics.StreaksLive do
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
    streak = Analytics.streak_data(opts)
    history_option = build_history_option(streak.per_trade_sequence)

    socket
    |> assign(streak: streak, history_option: history_option)
    |> push_event("chart-update", %{id: "streak-history", option: history_option})
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

  defp build_history_option(sequence) do
    bar_data =
      Enum.map(sequence, fn {result, r} ->
        color = if result == "WIN", do: "#22c55e", else: "#ef4444"
        %{value: r, itemStyle: %{color: color}}
      end)

    indices = Enum.with_index(sequence) |> Enum.map(fn {_, i} -> i + 1 end)

    %{
      tooltip: %{trigger: "axis"},
      xAxis: %{type: "category", data: indices, axisLabel: %{show: false}},
      yAxis: %{type: "value", name: "R"},
      grid: %{left: 50, right: 20, top: 10, bottom: 20},
      series: [
        %{
          type: "bar",
          data: bar_data,
          barMaxWidth: 8
        }
      ]
    }
  end

  defp streak_label(n) when n > 0, do: "+#{n}W"
  defp streak_label(n) when n < 0, do: "#{abs(n)}L"
  defp streak_label(0), do: "\u2014"
end

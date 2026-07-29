defmodule JournalexWeb.Analytics.BehaviorLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}
  alias JournalexWeb.Analytics.PeriodHelpers
  import JournalexWeb.AnalyticsFilterBar
  import JournalexWeb.InfoTooltip

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
    flags = Analytics.flags_impact(opts)

    # Total "cost" of negative flags: sum of (avg_on - avg_off) for flags where avg_on < avg_off
    total_cost =
      flags
      |> Enum.filter(fn {_, avg_on, avg_off, count_on, _} -> count_on > 0 and avg_on < avg_off end)
      |> Enum.map(fn {_, avg_on, avg_off, _, _} -> avg_off - avg_on end)
      |> Enum.sum()
      |> Float.round(3)

    assign(socket, flags: flags, total_flag_cost: total_cost)
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

  defp impact_color(avg_on, avg_off) when avg_on > avg_off, do: "text-emerald-600"
  defp impact_color(avg_on, avg_off) when avg_on < avg_off, do: "text-rose-600"
  defp impact_color(_, _), do: "text-zinc-500"
end

defmodule JournalexWeb.Analytics.EquityLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}

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
       equity: Analytics.equity_curve(versions: versions_available),
       streak: Analytics.streak_data(versions: versions_available)
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
  def handle_event("filter_dates", %{"from" => from, "to" => to}, socket) do
    {:noreply, reload(socket, from: from, to: to)}
  end

  @impl true
  def handle_event("set_r_mode", %{"mode" => mode}, socket) when mode in ["r", "usd", "both"] do
    Settings.set_analytics_r_mode(mode)
    {:noreply, reload(socket, r_mode: mode)}
  end

  defp reload(socket, changes) do
    socket = assign(socket, changes)
    a = socket.assigns
    opts = build_opts(a.selected_versions, a.from, a.to)
    assign(socket, equity: Analytics.equity_curve(opts), streak: Analytics.streak_data(opts))
  end

  defp build_opts(versions, from, to) do
    from_date = from && from != "" && Date.from_iso8601!(from)
    to_date = to && to != "" && Date.from_iso8601!(to)
    Enum.reject([versions: versions, from: from_date, to: to_date], fn {_, v} -> v == false or is_nil(v) end)
  end
end

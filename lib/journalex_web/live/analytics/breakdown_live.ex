defmodule JournalexWeb.Analytics.BreakdownLive do
  use JournalexWeb, :live_view

  alias Journalex.{Analytics, Settings}

  @impl true
  def mount(_params, _session, socket) do
    versions_available = Analytics.available_versions()

    {:ok,
     assign(socket,
       versions_available: versions_available,
       selected_versions: versions_available,
       from: nil,
       to: nil,
       r_mode: Settings.get_analytics_r_mode()
     )}
  end

  @impl true
  def handle_event("toggle_version", %{"version" => v_str}, socket) do
    v = String.to_integer(v_str)
    selected = socket.assigns.selected_versions
    new_selected = if v in selected, do: Enum.reject(selected, &(&1 == v)), else: Enum.sort([v | selected])
    {:noreply, assign(socket, selected_versions: new_selected)}
  end

  @impl true
  def handle_event("filter_dates", %{"from" => from, "to" => to}, socket) do
    {:noreply, assign(socket, from: from, to: to)}
  end

  @impl true
  def handle_event("set_r_mode", %{"mode" => mode}, socket) when mode in ["r", "usd", "both"] do
    Settings.set_analytics_r_mode(mode)
    {:noreply, assign(socket, r_mode: mode)}
  end
end

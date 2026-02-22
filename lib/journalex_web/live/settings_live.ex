defmodule JournalexWeb.SettingsLive do
  use JournalexWeb, :live_view

  alias Journalex.Settings

  @supported_versions [1, 2]

  @impl true
  def mount(_params, _session, socket) do
    current_version = Settings.get_default_metadata_version()
    auto_check_on_load = Settings.get_auto_check_on_load()
    r_size = Settings.get_r_size()
    activity_page_size = Settings.get_activity_page_size()
    filter_visible_weeks = Settings.get_filter_visible_weeks()
    summary_period_value = Settings.get_summary_period_value()
    summary_period_unit = Settings.get_summary_period_unit()

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:supported_versions, @supported_versions)
      |> assign(:default_metadata_version, current_version)
      |> assign(:auto_check_on_load, auto_check_on_load)
      |> assign(:r_size, r_size)
      |> assign(:activity_page_size, activity_page_size)
      |> assign(:filter_visible_weeks, filter_visible_weeks)
      |> assign(:summary_period_value, summary_period_value)
      |> assign(:summary_period_unit, summary_period_unit)
      |> assign(:save_status, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    version =
      params
      |> Map.get("default_metadata_version", "2")
      |> String.to_integer()

    # checkbox is only present in params when checked
    auto_check = Map.has_key?(params, "auto_check_on_load")

    r_size =
      case Float.parse(Map.get(params, "r_size", "8")) do
        {n, _} -> n
        :error  -> 8.0
      end

    activity_page_size =
      case Integer.parse(Map.get(params, "activity_page_size", "20")) do
        {n, _} when n > 0 -> n
        _ -> 20
      end

    filter_visible_weeks =
      case Integer.parse(Map.get(params, "filter_visible_weeks", "3")) do
        {n, _} when n > 0 -> n
        _ -> 3
      end

    summary_period_value =
      case Integer.parse(Map.get(params, "summary_period_value", "3")) do
        {n, _} when n > 0 -> n
        _ -> 3
      end

    summary_period_unit =
      case Map.get(params, "summary_period_unit", "week") do
        u when u in ["week", "day"] -> u
        _ -> "week"
      end

    with {:ok, _} <- Settings.set_default_metadata_version(version),
         {:ok, _} <- Settings.set_auto_check_on_load(auto_check),
         {:ok, _} <- Settings.set_r_size(r_size),
         {:ok, _} <- Settings.set_activity_page_size(activity_page_size),
         {:ok, _} <- Settings.set_filter_visible_weeks(filter_visible_weeks),
         {:ok, _} <- Settings.set_summary_period_value(summary_period_value),
         {:ok, _} <- Settings.set_summary_period_unit(summary_period_unit) do
      {:noreply,
       socket
       |> assign(:default_metadata_version, version)
       |> assign(:auto_check_on_load, auto_check)
       |> assign(:r_size, r_size)
       |> assign(:activity_page_size, activity_page_size)
       |> assign(:filter_visible_weeks, filter_visible_weeks)
       |> assign(:summary_period_value, summary_period_value)
       |> assign(:summary_period_unit, summary_period_unit)
       |> assign(:save_status, :ok)}
    else
      {:error, _changeset} ->
        {:noreply, assign(socket, :save_status, :error)}
    end
  end
end

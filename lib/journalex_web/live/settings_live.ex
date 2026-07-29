defmodule JournalexWeb.SettingsLive do
  use JournalexWeb, :live_view

  alias Journalex.Settings

  @supported_versions [1, 2, 3]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:supported_versions, @supported_versions)
      |> assign(:settings_form, build_settings_form())
      |> assign(:save_status, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_settings", %{"settings" => params}, socket) do
    {:noreply,
     socket
     |> assign(:settings_form, normalize_settings_form(params))
     |> assign(:save_status, nil)}
  end

  @impl true
  def handle_event("add_exception_day", _params, socket) do
    exception_days = socket.assigns.settings_form["analytics_exception_days"] || []

    {:noreply,
     update(socket, :settings_form, fn form ->
       Map.put(form, "analytics_exception_days", exception_days ++ [""])
     end)}
  end

  @impl true
  def handle_event("remove_exception_day", %{"index" => idx_str}, socket) do
    with {idx, _} <- Integer.parse(idx_str) do
      exception_days = socket.assigns.settings_form["analytics_exception_days"] || []

      next_days =
        exception_days
        |> List.delete_at(idx)
        |> ensure_exception_day_rows()

      {:noreply,
       socket
       |> update(:settings_form, &Map.put(&1, "analytics_exception_days", next_days))
       |> assign(:save_status, nil)}
    else
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    settings_form = normalize_settings_form(params)

    case persist_settings(settings_form) do
      :ok ->
        {:noreply,
         socket
         |> assign(:settings_form, build_settings_form())
         |> assign(:save_status, :ok)}

      :error ->
        {:noreply,
         socket
         |> assign(:settings_form, settings_form)
         |> assign(:save_status, :error)}
    end
  end

  defp build_settings_form do
    %{
      "default_metadata_version" => Integer.to_string(Settings.get_default_metadata_version()),
      "auto_check_on_load" => Settings.get_auto_check_on_load(),
      "r_size" => to_string(Settings.get_r_size()),
      "activity_page_size" => Integer.to_string(Settings.get_activity_page_size()),
      "filter_visible_weeks" => Integer.to_string(Settings.get_filter_visible_weeks()),
      "summary_period_value" => Integer.to_string(Settings.get_summary_period_value()),
      "summary_period_unit" => Settings.get_summary_period_unit(),
      "nav_pinned_pages" => Settings.get_nav_pinned_pages(),
      "analytics_exception_days" =>
        Settings.get_analytics_exception_days()
        |> Enum.map(&Date.to_iso8601/1)
        |> ensure_exception_day_rows()
    }
  end

  defp normalize_settings_form(params) do
    %{
      "default_metadata_version" =>
        params
        |> Map.get("default_metadata_version", "2")
        |> normalize_version(),
      "auto_check_on_load" => Map.has_key?(params, "auto_check_on_load"),
      "r_size" => Map.get(params, "r_size", ""),
      "activity_page_size" => Map.get(params, "activity_page_size", ""),
      "filter_visible_weeks" => Map.get(params, "filter_visible_weeks", ""),
      "summary_period_value" => Map.get(params, "summary_period_value", ""),
      "summary_period_unit" =>
        params
        |> Map.get("summary_period_unit", "week")
        |> normalize_summary_period_unit(),
      "nav_pinned_pages" =>
        params
        |> Map.get("nav_pinned_pages", %{})
        |> Map.keys(),
      "analytics_exception_days" =>
        params
        |> Map.get("analytics_exception_days", [])
        |> normalize_exception_day_inputs()
        |> ensure_exception_day_rows()
    }
  end

  defp persist_settings(settings_form) do
    version = parse_supported_version(settings_form["default_metadata_version"])
    auto_check = settings_form["auto_check_on_load"] == true
    r_size = parse_float_or_default(settings_form["r_size"], 8.0)
    activity_page_size = parse_positive_integer_or_default(settings_form["activity_page_size"], 20)
    filter_visible_weeks = parse_positive_integer_or_default(settings_form["filter_visible_weeks"], 3)
    summary_period_value = parse_positive_integer_or_default(settings_form["summary_period_value"], 3)
    summary_period_unit = normalize_summary_period_unit(settings_form["summary_period_unit"])
    nav_pinned_pages = settings_form["nav_pinned_pages"] || []
    exception_days = settings_form["analytics_exception_days"] || []

    with {:ok, _} <- Settings.set_default_metadata_version(version),
         {:ok, _} <- Settings.set_auto_check_on_load(auto_check),
         {:ok, _} <- Settings.set_r_size(r_size),
         {:ok, _} <- Settings.set_activity_page_size(activity_page_size),
         {:ok, _} <- Settings.set_filter_visible_weeks(filter_visible_weeks),
         {:ok, _} <- Settings.set_summary_period_value(summary_period_value),
         {:ok, _} <- Settings.set_summary_period_unit(summary_period_unit),
         {:ok, _} <- Settings.set_nav_pinned_pages(nav_pinned_pages),
         {:ok, _} <- Settings.set_analytics_exception_days(exception_days) do
      :ok
    else
      _ -> :error
    end
  end

  defp normalize_version(version) do
    version_string = to_string(version)
    if version_string in Enum.map(@supported_versions, &Integer.to_string/1), do: version_string, else: "2"
  end

  defp parse_supported_version(version) do
    case Integer.parse(to_string(version)) do
      {parsed, _} when parsed in @supported_versions -> parsed
      _ -> 2
    end
  end

  defp normalize_summary_period_unit(unit) when unit in ["week", "day"], do: unit
  defp normalize_summary_period_unit(_unit), do: "week"

  defp parse_float_or_default(value, default) do
    case Float.parse(to_string(value)) do
      {parsed, _} -> parsed
      :error -> default
    end
  end

  defp parse_positive_integer_or_default(value, default) do
    case Integer.parse(to_string(value)) do
      {parsed, _} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_exception_day_inputs(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp normalize_exception_day_inputs(value) when is_binary(value), do: [value]
  defp normalize_exception_day_inputs(_value), do: []

  defp ensure_exception_day_rows([]), do: [""]
  defp ensure_exception_day_rows(rows), do: rows
end

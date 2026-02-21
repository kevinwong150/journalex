defmodule JournalexWeb.SettingsLive do
  use JournalexWeb, :live_view

  alias Journalex.Settings

  @supported_versions [1, 2]

  @impl true
  def mount(_params, _session, socket) do
    current_version = Settings.get_default_metadata_version()
    auto_check_on_load = Settings.get_auto_check_on_load()

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:supported_versions, @supported_versions)
      |> assign(:default_metadata_version, current_version)
      |> assign(:auto_check_on_load, auto_check_on_load)
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

    with {:ok, _} <- Settings.set_default_metadata_version(version),
         {:ok, _} <- Settings.set_auto_check_on_load(auto_check) do
      {:noreply,
       socket
       |> assign(:default_metadata_version, version)
       |> assign(:auto_check_on_load, auto_check)
       |> assign(:save_status, :ok)}
    else
      {:error, _changeset} ->
        {:noreply, assign(socket, :save_status, :error)}
    end
  end
end

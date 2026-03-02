defmodule JournalexWeb.MetadataDraftLive do
  @moduledoc """
  LiveView page for managing named metadata draft templates.

  Two-column inline layout:
  - Left panel: list of existing drafts (name, version badge, Edit / Delete)
  - Right panel: create or edit form reusing MetadataForm.v1 / MetadataForm.v2
  """
  use JournalexWeb, :live_view

  alias Journalex.MetadataDrafts
  alias Journalex.MetadataDrafts.Draft

  @supported_versions [1, 2]

  @impl true
  def mount(_params, _session, socket) do
    drafts = MetadataDrafts.list_drafts()

    socket =
      socket
      |> assign(:drafts, drafts)
      |> assign(:supported_versions, @supported_versions)
      |> assign(:form_version, Journalex.Settings.get_default_metadata_version())
      |> assign(:editing_draft, nil)
      |> assign(:draft_name, "")
      |> assign(:draft_metadata, %{})
      |> assign(:bulk_mode, false)
      |> assign(:bulk_count, 2)
      |> assign(:bulk_names, List.duplicate("", 2))
      |> assign(:select_mode, false)
      |> assign(:selected_ids, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_event("new_draft", _params, socket) do
    socket =
      socket
      |> assign(:editing_draft, nil)
      |> assign(:draft_name, "")
      |> assign(:draft_metadata, %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = MetadataDrafts.get_draft!(id)

    socket =
      socket
      |> assign(:editing_draft, draft)
      |> assign(:draft_name, draft.name)
      |> assign(:form_version, draft.metadata_version)
      |> assign(:draft_metadata, draft.metadata || %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = MetadataDrafts.get_draft!(id)

    case MetadataDrafts.delete_draft(draft) do
      {:ok, _} ->
        drafts = MetadataDrafts.list_drafts()

        # If we were editing the deleted draft, clear the form
        editing = socket.assigns.editing_draft

        socket =
          if editing && editing.id == draft.id do
            socket
            |> assign(:editing_draft, nil)
            |> assign(:draft_name, "")
            |> assign(:draft_metadata, %{})
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:drafts, drafts)
         |> put_flash(:info, "Draft \"#{draft.name}\" deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete draft")}
    end
  end

  @impl true
  def handle_event("change_draft_version", %{"version" => version_str}, socket) do
    {version, _} = Integer.parse(version_str)

    if version in @supported_versions do
      {:noreply, assign(socket, :form_version, version)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_draft", params, socket) do
    name = String.trim(params["draft_name"] || socket.assigns.draft_name || "")
    version = socket.assigns.form_version

    metadata = build_metadata_from_params(params, version)

    attrs = %{
      name: name,
      metadata_version: version,
      metadata: metadata
    }

    result =
      case socket.assigns.editing_draft do
        nil -> MetadataDrafts.create_draft(attrs)
        %Draft{} = draft -> MetadataDrafts.update_draft(draft, attrs)
      end

    case result do
      {:ok, saved_draft} ->
        drafts = MetadataDrafts.list_drafts()

        action = if socket.assigns.editing_draft, do: "updated", else: "created"

        {:noreply,
         socket
         |> assign(:drafts, drafts)
         |> assign(:editing_draft, saved_draft)
         |> assign(:draft_name, saved_draft.name)
         |> assign(:draft_metadata, saved_draft.metadata || %{})
         |> put_flash(:info, "Draft \"#{saved_draft.name}\" #{action}")}

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Failed to save draft: #{errors}")}
    end
  end

  @impl true
  def handle_event("duplicate_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    draft = MetadataDrafts.get_draft!(id)

    new_name = draft.name <> " (copy)"

    case MetadataDrafts.create_draft(%{
           name: new_name,
           metadata_version: draft.metadata_version,
           metadata: draft.metadata || %{}
         }) do
      {:ok, new_draft} ->
        drafts = MetadataDrafts.list_drafts()

        {:noreply,
         socket
         |> assign(:drafts, drafts)
         |> assign(:editing_draft, new_draft)
         |> assign(:draft_name, new_draft.name)
         |> assign(:form_version, new_draft.metadata_version)
         |> assign(:draft_metadata, new_draft.metadata || %{})
         |> put_flash(:info, "Draft duplicated as \"#{new_name}\"")}

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Failed to duplicate: #{errors}")}
    end
  end

  @impl true
  def handle_event("toggle_bulk_mode", _params, socket) do
    {:noreply, assign(socket, :bulk_mode, !socket.assigns.bulk_mode)}
  end

  @impl true
  def handle_event("add_bulk_field", _params, socket) do
    bulk_names = socket.assigns.bulk_names ++ [""]
    {:noreply, socket |> assign(:bulk_names, bulk_names) |> assign(:bulk_count, length(bulk_names))}
  end

  @impl true
  def handle_event("remove_bulk_field", _params, socket) do
    current = socket.assigns.bulk_names
    bulk_names = if length(current) > 2, do: Enum.drop(current, -1), else: current
    {:noreply, socket |> assign(:bulk_names, bulk_names) |> assign(:bulk_count, length(bulk_names))}
  end

  @impl true
  def handle_event("update_bulk_name", %{"index" => idx_str, "value" => name}, socket) do
    {idx, _} = Integer.parse(idx_str)
    bulk_names = List.replace_at(socket.assigns.bulk_names, idx, name)
    {:noreply, assign(socket, :bulk_names, bulk_names)}
  end

  @impl true
  def handle_event("create_bulk_drafts", _params, socket) do
    version = socket.assigns.form_version

    names =
      socket.assigns.bulk_names
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if names == [] do
      {:noreply, put_flash(socket, :error, "Please enter at least one draft name")}
    else
      results =
        Enum.map(names, fn name ->
          MetadataDrafts.create_draft(%{name: name, metadata_version: version, metadata: %{}})
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))
      created = Enum.count(results, &match?({:ok, _}, &1))

      socket =
        if errors == [] do
          socket
          |> assign(:drafts, MetadataDrafts.list_drafts())
          |> assign(:bulk_mode, false)
          |> assign(:bulk_count, 2)
          |> assign(:bulk_names, List.duplicate("", 2))
          |> put_flash(:info, "Created #{created} draft(s)")
        else
          failed = Enum.map(errors, fn {:error, cs} ->
            cs.errors |> Enum.map(fn {f, {m, _}} -> "#{f}: #{m}" end) |> Enum.join(", ")
          end)
          socket
          |> assign(:drafts, MetadataDrafts.list_drafts())
          |> put_flash(:error, "#{created} created; #{length(errors)} failed: #{Enum.join(failed, " | ")}")
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_select_mode", _params, socket) do
    select_mode = !socket.assigns.select_mode

    socket =
      socket
      |> assign(:select_mode, select_mode)
      |> assign(:selected_ids, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select_draft", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_ids = Enum.map(socket.assigns.drafts, & &1.id) |> MapSet.new()
    currently_selected = socket.assigns.selected_ids

    selected =
      if MapSet.equal?(currently_selected, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("delete_selected_drafts", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    results =
      Enum.map(ids, fn id ->
        draft = MetadataDrafts.get_draft!(id)
        MetadataDrafts.delete_draft(draft)
      end)

    deleted = Enum.count(results, &match?({:ok, _}, &1))
    failed  = Enum.count(results, &match?({:error, _}, &1))

    drafts = MetadataDrafts.list_drafts()

    # Clear editing panel if the edited draft was among the deleted
    editing = socket.assigns.editing_draft

    socket =
      if editing && MapSet.member?(socket.assigns.selected_ids, editing.id) do
        socket
        |> assign(:editing_draft, nil)
        |> assign(:draft_name, "")
        |> assign(:draft_metadata, %{})
      else
        socket
      end

    flash_msg =
      if failed == 0,
        do: "Deleted #{deleted} draft(s)",
        else: "Deleted #{deleted}, failed to delete #{failed}"

    flash_level = if failed == 0, do: :info, else: :error

    {:noreply,
     socket
     |> assign(:drafts, drafts)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:select_mode, false)
     |> put_flash(flash_level, flash_msg)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto mt-8 px-4 pb-10">
      <%!-- Page header --%>
      <div class="mb-6 flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-zinc-900">Metadata Drafts</h1>
          <p class="text-sm text-zinc-500 mt-1">
            Save and reuse metadata templates for trade journal entries.
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button
            phx-click="toggle_bulk_mode"
            class={[
              "inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium transition-colors shadow-sm",
              if(@bulk_mode,
                do: "bg-amber-100 text-amber-800 border border-amber-300 hover:bg-amber-200",
                else: "bg-zinc-100 text-zinc-700 border border-zinc-200 hover:bg-zinc-200"
              )
            ]}
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
            </svg>
            Bulk Create
          </button>
          <button
            phx-click="new_draft"
            class="inline-flex items-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-green-600 text-white hover:bg-green-700 transition-colors shadow-sm"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
            New Draft
          </button>
        </div>
      </div>

      <%!-- Bulk Create panel --%>
      <div :if={@bulk_mode} class="mb-6 bg-amber-50 border border-amber-200 rounded-lg shadow-sm overflow-hidden">
        <div class="px-5 py-3 border-b border-amber-200 bg-amber-100/60 flex items-center justify-between">
          <h3 class="text-xs font-semibold text-amber-800 uppercase tracking-wide">Bulk Create Drafts</h3>
          <div class="flex items-center gap-3">
            <span class="text-xs text-amber-700">Version:</span>
            <%= for version <- @supported_versions do %>
              <button
                type="button"
                phx-click="change_draft_version"
                phx-value-version={version}
                class={[
                  "px-2.5 py-0.5 text-xs font-semibold rounded-md transition-colors",
                  if(@form_version == version,
                    do: "bg-amber-600 text-white",
                    else: "bg-white text-amber-700 border border-amber-300 hover:bg-amber-50"
                  )
                ]}
              >
                V{version}
              </button>
            <% end %>
          </div>
        </div>
        <div class="p-5 space-y-4">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-amber-800 shrink-0">Fields:</span>
            <div class="flex items-center gap-1.5">
              <button
                type="button"
                phx-click="remove_bulk_field"
                disabled={length(@bulk_names) <= 2}
                class="w-7 h-7 inline-flex items-center justify-center rounded-md border border-amber-300 bg-white text-amber-700 hover:bg-amber-50 hover:border-amber-400 hover:text-amber-900 active:bg-amber-200 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-white disabled:hover:border-amber-300 disabled:hover:text-amber-700 disabled:active:scale-100 transition-all text-base font-bold leading-none select-none"
              >−</button>
              <span class="w-6 text-center text-sm font-semibold text-amber-800">{length(@bulk_names)}</span>
              <button
                type="button"
                phx-click="add_bulk_field"
                disabled={length(@bulk_names) >= 50}
                class="w-7 h-7 inline-flex items-center justify-center rounded-md border border-amber-300 bg-white text-amber-700 hover:bg-amber-50 hover:border-amber-400 hover:text-amber-900 active:bg-amber-200 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-white disabled:hover:border-amber-300 disabled:hover:text-amber-700 disabled:active:scale-100 transition-all text-base font-bold leading-none select-none"
              >+</button>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
            <%= for {name, idx} <- Enum.with_index(@bulk_names) do %>
              <div class="flex items-center gap-1.5">
                <span class="text-xs text-amber-600 w-5 shrink-0 text-right">{idx + 1}.</span>
                <input
                  type="text"
                  value={name}
                  placeholder={"Draft #{idx + 1} name"}
                  phx-keyup="update_bulk_name"
                  phx-value-index={idx}
                  class="flex-1 min-w-0 rounded-md border border-amber-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>
            <% end %>
          </div>

          <div class="flex items-center justify-end gap-2 pt-1">
            <button
              type="button"
              phx-click="toggle_bulk_mode"
              class="px-3 py-2 text-sm font-medium text-zinc-600 bg-white border border-zinc-300 rounded-md hover:bg-zinc-50 transition-colors"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="create_bulk_drafts"
              class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-amber-600 text-white rounded-md hover:bg-amber-700 transition-colors shadow-sm"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              Create All
            </button>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Left panel: Draft list --%>
        <div class="lg:col-span-1">
          <div class="bg-white rounded-lg border border-zinc-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-zinc-100 bg-zinc-50 flex items-center justify-between">
              <h3 class="text-xs font-semibold text-zinc-600 uppercase tracking-wide">
                Saved Drafts
              </h3>
              <div class="flex items-center gap-2">
                <span :if={@select_mode && @drafts != []} class="text-xs text-zinc-500 cursor-pointer hover:text-zinc-800" phx-click="toggle_select_all">
                  {if MapSet.size(@selected_ids) == length(@drafts), do: "Deselect all", else: "Select all"}
                </span>
                <button
                  phx-click="toggle_select_mode"
                  class={[
                    "text-xs px-2 py-0.5 rounded-md border font-medium transition-colors",
                    if(@select_mode,
                      do: "bg-red-100 text-red-700 border-red-300 hover:bg-red-200",
                      else: "bg-zinc-100 text-zinc-600 border-zinc-200 hover:bg-zinc-200"
                    )
                  ]}
                >
                  {if @select_mode, do: "Cancel", else: "Select"}
                </button>
                <span class="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-zinc-200 text-zinc-600">
                  {length(@drafts)}
                </span>
              </div>
            </div>

            <%= if @drafts == [] do %>
              <div class="px-4 py-10 text-center">
                <svg
                  class="mx-auto w-8 h-8 text-zinc-300 mb-2"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                  />
                </svg>
                <p class="text-sm text-zinc-400">No drafts yet.</p>
                <p class="text-xs text-zinc-400 mt-0.5">Create one using the form on the right.</p>
              </div>
            <% else %>
              <ul class="divide-y divide-zinc-100">
                <%= for draft <- @drafts do %>
                  <li class={[
                    "px-3 py-3 transition-colors border-l-[3px]",
                    if(@editing_draft && @editing_draft.id == draft.id,
                      do: "bg-blue-100 border-blue-500 shadow-sm",
                      else: "border-transparent hover:bg-zinc-50"
                    )
                  ]}>
                    <div class="flex items-start justify-between gap-1.5">
                      <%!-- Checkbox (only in select mode) --%>
                      <div :if={@select_mode} class="flex items-center pt-0.5 mr-1 shrink-0">
                        <input
                          type="checkbox"
                          checked={MapSet.member?(@selected_ids, draft.id)}
                          phx-click="toggle_select_draft"
                          phx-value-id={draft.id}
                          class="w-4 h-4 rounded border-zinc-300 text-red-600 cursor-pointer"
                        />
                      </div>
                      <div class="min-w-0 flex-1">
                        <div class="flex items-center gap-1.5">
                          <svg
                            :if={draft.inserted_at != draft.updated_at}
                            class="w-3 h-3 shrink-0 text-amber-400"
                            fill="currentColor"
                            viewBox="0 0 24 24"
                            title="Modified after creation"
                          >
                            <path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 000-1.41l-2.34-2.34a1 1 0 00-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/>
                          </svg>
                          <p class={[
                            "text-sm font-medium truncate",
                            if(@editing_draft && @editing_draft.id == draft.id,
                              do: "text-blue-700 font-semibold",
                              else: "text-zinc-900"
                            )
                          ]}>
                            {draft.name}
                          </p>
                        </div>
                        <div class="flex items-center gap-1.5 mt-1">
                          <span class={[
                            "inline-flex items-center px-1.5 py-0.5 text-[10px] font-semibold rounded",
                            if(draft.metadata_version == 1,
                              do: "bg-indigo-100 text-indigo-700",
                              else: "bg-blue-100 text-blue-700"
                            )
                          ]}>
                            V{draft.metadata_version}
                          </span>
                          <span class="text-[10px] text-zinc-400">
                            {Calendar.strftime(draft.updated_at, "%b %d, %H:%M")}
                          </span>
                        </div>
                      </div>
                      <div :if={!@select_mode} class="flex items-center gap-0.5 shrink-0">
                        <button
                          phx-click="edit_draft"
                          phx-value-id={draft.id}
                          class="p-1.5 rounded text-zinc-400 hover:text-blue-600 hover:bg-blue-50 transition-colors"
                          title="Edit"
                        >
                          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                            />
                          </svg>
                        </button>
                        <button
                          phx-click="duplicate_draft"
                          phx-value-id={draft.id}
                          class="p-1.5 rounded text-zinc-400 hover:text-green-600 hover:bg-green-50 transition-colors"
                          title="Duplicate"
                        >
                          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                            />
                          </svg>
                        </button>
                        <button
                          phx-click="delete_draft"
                          phx-value-id={draft.id}
                          class="p-1.5 rounded text-zinc-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                          title="Delete"
                          data-confirm={"Delete draft \"#{draft.name}\"?"}
                        >
                          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                            />
                          </svg>
                        </button>
                      </div>
                    </div>
                  </li>
                <% end %>
              </ul>
              <%!-- Bulk delete footer --%>
              <div :if={@select_mode && MapSet.size(@selected_ids) > 0} class="px-3 py-2 border-t border-red-100 bg-red-50">
                <button
                  phx-click="delete_selected_drafts"
                  data-confirm={"Delete #{MapSet.size(@selected_ids)} selected draft(s)? This cannot be undone."}
                  class="w-full inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-md text-sm font-medium bg-red-600 text-white hover:bg-red-700 transition-colors shadow-sm"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                  Delete {MapSet.size(@selected_ids)} selected
                </button>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Right panel: Create/Edit form --%>
        <div class="lg:col-span-2">
          <div class="bg-white rounded-lg border border-zinc-200 shadow-sm">
            <div class="px-4 py-3 border-b border-zinc-100 bg-zinc-50">
              <div class="flex items-center justify-between">
                <h3 class="text-xs font-semibold text-zinc-600 uppercase tracking-wide">
                  {if @editing_draft, do: "Edit Draft — #{@editing_draft.name}", else: "New Draft"}
                </h3>
                <div class="flex items-center gap-1.5">
                  <%= for version <- @supported_versions do %>
                    <button
                      type="button"
                      phx-click="change_draft_version"
                      phx-value-version={version}
                      class={[
                        "px-3 py-1 text-xs font-semibold rounded-md transition-colors",
                        if(@form_version == version,
                          do: "bg-blue-600 text-white shadow-sm",
                          else: "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                        )
                      ]}
                    >
                      V{version}
                    </button>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="p-4 space-y-4">
              <%!-- Draft name input --%>
              <div>
                <label for="draft-name" class="block text-sm font-medium text-zinc-700 mb-1.5">
                  Draft Name
                </label>
                <input
                  type="text"
                  id="draft-name"
                  value={@draft_name}
                  phx-hook="DraftNameSync"
                  data-target-id="hidden-draft-name-0"
                  placeholder="e.g. My Quick Loss Template"
                  class="w-full px-3 py-2 text-sm border border-zinc-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <%!-- Metadata form (reuse existing components) --%>
              <% synthetic_item = %{
                metadata: @draft_metadata,
                metadata_version: @form_version,
                result: nil,
                realized_pl: nil,
                action_chain: nil,
                datetime: nil,
                ticker: nil
              } %>

              <%= case @form_version do %>
                <% 1 -> %>
                  <JournalexWeb.MetadataForm.v1
                    item={synthetic_item}
                    idx={0}
                    on_save_event="save_draft"
                    draft_name={@draft_name}
                  />
                <% 2 -> %>
                  <JournalexWeb.MetadataForm.v2
                    item={synthetic_item}
                    idx={0}
                    on_save_event="save_draft"
                    draft_name={@draft_name}
                  />
                <% _ -> %>
                  <div class="text-center text-sm text-zinc-500 py-4">
                    Unsupported version: {@form_version}
                  </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Build metadata map from form params, same logic as TradesDumpLive but without trade-specific fields
  defp build_metadata_from_params(params, version) do
    case version do
      1 -> build_v1_metadata(params)
      2 -> build_v2_metadata(params)
      _ -> %{}
    end
  end

  defp build_v1_metadata(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      operation_mistake?: params["operation_mistake"] == "true",
      follow_setup?: params["follow_setup"] == "true",
      follow_stop_loss_management?: params["follow_stop_loss_management"] == "true",
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      unnecessary_trade?: params["unnecessary_trade"] == "true",
      close_time_comment: join_close_time_comments(params["close_time_comment"])
    }
  end

  defp build_v2_metadata(params) do
    %{
      done?: params["done"] == "true",
      lost_data?: params["lost_data"] == "true",
      rank: parse_string(params["rank"]),
      setup: parse_string(params["setup"]),
      close_trigger: parse_string(params["close_trigger"]),
      order_type: parse_string(params["order_type"]),
      revenge_trade?: params["revenge_trade"] == "true",
      fomo?: params["fomo"] == "true",
      add_size?: params["add_size"] == "true",
      adjusted_risk_reward?: params["adjusted_risk_reward"] == "true",
      align_with_trend?: params["align_with_trend"] == "true",
      better_risk_reward_ratio?: params["better_risk_reward_ratio"] == "true",
      big_picture?: params["big_picture"] == "true",
      earning_report?: params["earning_report"] == "true",
      follow_up_trial?: params["follow_up_trial"] == "true",
      good_lesson?: params["good_lesson"] == "true",
      hot_sector?: params["hot_sector"] == "true",
      momentum?: params["momentum"] == "true",
      news?: params["news"] == "true",
      normal_emotion?: params["normal_emotion"] == "true",
      operation_mistake?: params["operation_mistake"] == "true",
      overnight?: params["overnight"] == "true",
      overnight_in_purpose?: params["overnight_in_purpose"] == "true",
      slipped_position?: params["slipped_position"] == "true",
      choppychart?: params["choppychart"] == "true",
      close_trade_remorse?: params["close_trade_remorse"] == "true",
      initial_risk_reward_ratio: parse_decimal(params["initial_risk_reward_ratio"]),
      best_risk_reward_ratio: (if params["best_rr_enabled"] == "true", do: parse_decimal(params["best_risk_reward_ratio"]), else: Decimal.new("0")),
      size: parse_decimal(params["size"]),
      close_time_comment: join_close_time_comments(params["close_time_comment"])
    }
  end

  defp parse_string(nil), do: nil
  defp parse_string(""), do: nil
  defp parse_string(str) when is_binary(str), do: String.trim(str)

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil
  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp join_close_time_comments(nil), do: nil
  defp join_close_time_comments([]), do: nil
  defp join_close_time_comments(list) when is_list(list) do
    joined = list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(", ")
    if joined == "", do: nil, else: joined
  end
  defp join_close_time_comments(str) when is_binary(str), do: parse_string(str)
end

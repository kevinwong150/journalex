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
  def handle_event("update_draft_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :draft_name, name)}
  end

  @impl true
  def handle_event("save_draft", params, socket) do
    name = String.trim(socket.assigns.draft_name)
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
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">Metadata Drafts</h1>
        <button
          phx-click="new_draft"
          class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-green-600 text-white hover:bg-green-700"
        >
          + New Draft
        </button>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Left panel: Draft list --%>
        <div class="lg:col-span-1">
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm overflow-hidden">
            <div class="px-4 py-3 border-b border-gray-100 bg-gray-50">
              <h3 class="text-sm font-semibold text-gray-700">
                Saved Drafts
                <span class="text-gray-400 font-normal">({length(@drafts)})</span>
              </h3>
            </div>

            <%= if @drafts == [] do %>
              <div class="px-4 py-8 text-center text-sm text-gray-400">
                No drafts yet. Create one to get started.
              </div>
            <% else %>
              <ul class="divide-y divide-gray-100">
                <%= for draft <- @drafts do %>
                  <li class={[
                    "px-4 py-3 hover:bg-gray-50 transition-colors",
                    if(@editing_draft && @editing_draft.id == draft.id, do: "bg-blue-50 border-l-2 border-blue-500", else: "")
                  ]}>
                    <div class="flex items-start justify-between gap-2">
                      <div class="min-w-0 flex-1">
                        <p class="text-sm font-medium text-gray-900 truncate">
                          {draft.name}
                        </p>
                        <div class="flex items-center gap-2 mt-1">
                          <span class={[
                            "inline-flex items-center px-1.5 py-0.5 text-[10px] font-medium rounded",
                            if(draft.metadata_version == 1,
                              do: "bg-indigo-100 text-indigo-700",
                              else: "bg-blue-100 text-blue-700"
                            )
                          ]}>
                            V{draft.metadata_version}
                          </span>
                          <span class="text-[10px] text-gray-400">
                            {Calendar.strftime(draft.updated_at, "%b %d, %H:%M")}
                          </span>
                        </div>
                      </div>
                      <div class="flex items-center gap-1 shrink-0">
                        <button
                          phx-click="edit_draft"
                          phx-value-id={draft.id}
                          class="p-1 text-gray-400 hover:text-blue-600 transition-colors"
                          title="Edit"
                        >
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                          </svg>
                        </button>
                        <button
                          phx-click="duplicate_draft"
                          phx-value-id={draft.id}
                          class="p-1 text-gray-400 hover:text-green-600 transition-colors"
                          title="Duplicate"
                        >
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                          </svg>
                        </button>
                        <button
                          phx-click="delete_draft"
                          phx-value-id={draft.id}
                          class="p-1 text-gray-400 hover:text-red-600 transition-colors"
                          title="Delete"
                          data-confirm={"Delete draft \"#{draft.name}\"?"}
                        >
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                          </svg>
                        </button>
                      </div>
                    </div>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>

        <%!-- Right panel: Create/Edit form --%>
        <div class="lg:col-span-2">
          <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
            <div class="px-4 py-3 border-b border-gray-100 bg-gray-50">
              <div class="flex items-center justify-between">
                <h3 class="text-sm font-semibold text-gray-700">
                  {if @editing_draft, do: "Edit Draft", else: "New Draft"}
                </h3>
                <div class="flex items-center gap-2">
                  <%= for version <- @supported_versions do %>
                    <button
                      type="button"
                      phx-click="change_draft_version"
                      phx-value-version={version}
                      class={[
                        "px-3 py-1 text-xs font-medium rounded-md transition-colors",
                        if(@form_version == version,
                          do: "bg-blue-600 text-white shadow-sm",
                          else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
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
                <label for="draft-name" class="block text-sm font-medium text-gray-700 mb-1">
                  Draft Name
                </label>
                <input
                  type="text"
                  id="draft-name"
                  value={@draft_name}
                  phx-keyup="update_draft_name"
                  placeholder="e.g. My Quick Loss Template"
                  class="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <%!-- Metadata form (reuse existing components) --%>
              <% synthetic_item = %{
                metadata: @draft_metadata,
                metadata_version: @form_version,
                # Provide dummy fields that MetadataForm may read
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
                    on_reset_event={nil}
                  />
                <% 2 -> %>
                  <JournalexWeb.MetadataForm.v2
                    item={synthetic_item}
                    idx={0}
                    on_save_event="save_draft"
                    on_reset_event={nil}
                  />
                <% _ -> %>
                  <div class="text-center text-sm text-gray-500 py-4">
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
      initial_risk_reward_ratio: parse_decimal(params["initial_risk_reward_ratio"]),
      best_risk_reward_ratio: parse_decimal(params["best_risk_reward_ratio"]),
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

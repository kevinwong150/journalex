defmodule JournalexWeb.StatementDumpLive do
  use JournalexWeb, :live_view

  alias Journalex.Activity
  alias JournalexWeb.ActivityStatementList

  @impl true
  def mount(_params, _session, socket) do
    statements = Activity.list_all_activity_statements()

    socket =
      socket
      |> assign(:statements, statements)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:all_selected?, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    all_ids = socket.assigns.statements |> Enum.map(& &1.id) |> MapSet.new()

    {selected_ids, all_selected?} =
      if socket.assigns.all_selected? do
        {MapSet.new(), false}
      else
        {all_ids, true}
      end

    {:noreply, assign(socket, selected_ids: selected_ids, all_selected?: all_selected?)}
  end

  def handle_event("toggle_row", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    all_ids = socket.assigns.statements |> Enum.map(& &1.id) |> MapSet.new()
    all_selected? = MapSet.equal?(selected, all_ids) and MapSet.size(all_ids) > 0

    {:noreply, assign(socket, selected_ids: selected, all_selected?: all_selected?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">Statement Dump</h1>
        <div class="flex items-center gap-3">
          <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
            Selected: <%= MapSet.size(@selected_ids) %>
          </span>
          <button
            phx-click="toggle_select_all"
            class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white hover:bg-gray-50"
          >
            <%= if @all_selected?, do: "Clear All", else: "Select All" %>
          </button>
        </div>
      </div>

      <ActivityStatementList.list
        id="statement-dump"
        title="All Statements"
        count={length(@statements)}
        rows={@statements}
        expanded={true}
        show_save_controls?={false}
        show_values?={true}
        selectable?={true}
        selected_ids={@selected_ids}
        all_selected?={@all_selected?}
        on_toggle_row_event="toggle_row"
        on_toggle_all_event="toggle_select_all"
      />
    </div>
    """
  end
end

defmodule JournalexWeb.StatementDumpLive do
  use JournalexWeb, :live_view

  alias Journalex.Activity
  alias JournalexWeb.ActivityStatementList
  alias Journalex.Notion
  alias Journalex.Notion.Client, as: NotionClient

  @impl true
  def mount(_params, _session, socket) do
    statements = Activity.list_all_activity_statements()

    socket =
      socket
      |> assign(:statements, statements)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:all_selected?, false)
      |> assign(:row_statuses, %{})
      |> assign(:notion_exists_count, 0)
      |> assign(:notion_missing_count, 0)
      |> assign(:notion_conn_status, :unknown)
      |> assign(:notion_conn_message, nil)
      |> assign(:hide_exists?, false)

    # Kick off an automatic Notion check after the socket connects
    if connected?(socket), do: send(self(), :auto_check_notion)

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

  def handle_event("check_notion", _params, socket) do
    selected_ids = socket.assigns.selected_ids
    statements = socket.assigns.statements

    selected_rows = Enum.filter(statements, fn s -> MapSet.member?(selected_ids, s.id) end)

    # New logic: bulk fetch all Notion records and compare via Trademark field
    case Notion.list_all_trademarks() do
      {:ok, trademark_set} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(selected_rows, {%{}, 0, 0}, fn row, {acc, ec, mc} ->
            # Trademark format mirrors creation: "<Ticker>@<ISO8601(datetime)>"
            title = row.symbol <> "@" <> DateTime.to_iso8601(row.datetime)

            if MapSet.member?(trademark_set, title) do
              {Map.put(acc, row.id, :exists), ec + 1, mc}
            else
              {Map.put(acc, row.id, :missing), ec, mc + 1}
            end
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count
         )}

      {:error, reason} ->
        msg = inspect(reason)
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(selected_rows, {%{}, 0, 0}, fn row, {acc, ec, mc} ->
            {Map.put(acc, row.id, :error), ec, mc}
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count,
           notion_conn_status: :error,
           notion_conn_message: "Failed to fetch Notion records: " <> msg
         )}
    end
  end

  def handle_event("insert_missing_notion", _params, socket) do
    selected_ids = socket.assigns.selected_ids
    statements = socket.assigns.statements
    statuses = socket.assigns.row_statuses || %{}

    selected_rows = Enum.filter(statements, fn s -> MapSet.member?(selected_ids, s.id) end)

    {row_statuses, exists_count, missing_count} =
      Enum.reduce(selected_rows, {statuses, 0, 0}, fn row, {acc, ec, mc} ->
        with {:ok, exists?} <- Notion.exists_by_timestamp_and_ticker?(row.datetime, row.symbol),
             false <- exists?,
             {:ok, _page} <- Notion.create_from_statement(row) do
          {Map.put(acc, row.id, :exists), ec + 1, mc}
        else
          # exists? was true -> already exists
          true -> {Map.put(acc, row.id, :exists), ec + 1, mc}
          # any API error (exists? check or create)
          {:error, _} -> {Map.put(acc, row.id, :error), ec, mc}
        end
      end)

    {:noreply,
     assign(socket,
       row_statuses: row_statuses,
       notion_exists_count: exists_count,
       notion_missing_count: missing_count
     )}
  end

  def handle_event("clear_row_statuses", _params, socket) do
    {:noreply,
     assign(socket,
       row_statuses: %{},
       notion_exists_count: 0,
       notion_missing_count: 0
     )}
  end

  def handle_event("toggle_hide_exists", _params, socket) do
    {:noreply, assign(socket, hide_exists?: !socket.assigns.hide_exists?)}
  end

  def handle_event("check_notion_connection", _params, socket) do
    user_res = NotionClient.me()

    notion_conf = Application.get_env(:journalex, Journalex.Notion, [])
    ds_id = Keyword.get(notion_conf, :data_source_id)
    db_res = if ds_id, do: NotionClient.retrieve_database(ds_id), else: {:ok, :no_db_configured}

    case {user_res, db_res} do
      {{:ok, _user}, {:ok, :no_db_configured}} ->
        {:noreply,
         assign(socket,
           notion_conn_status: :ok,
           notion_conn_message: "No data source configured; token valid"
         )}

      {{:ok, _user}, {:ok, _db}} ->
        {:noreply, assign(socket, notion_conn_status: :ok, notion_conn_message: nil)}

      {err1, err2} ->
        msg = format_conn_error(err1, err2)
        {:noreply, assign(socket, notion_conn_status: :error, notion_conn_message: msg)}
    end
  end

  # Auto-run Notion check for all statements on initial page load
  @impl true
  def handle_info(:auto_check_notion, socket) do
    rows = socket.assigns.statements || []

    case Notion.list_all_trademarks() do
      {:ok, trademark_set} ->
        {row_statuses, exists_count, missing_count} =
          Enum.reduce(rows, {%{}, 0, 0}, fn row, {acc, ec, mc} ->
            title = row.symbol <> "@" <> DateTime.to_iso8601(row.datetime)

            if MapSet.member?(trademark_set, title) do
              {Map.put(acc, row.id, :exists), ec + 1, mc}
            else
              {Map.put(acc, row.id, :missing), ec, mc + 1}
            end
          end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_exists_count: exists_count,
           notion_missing_count: missing_count,
           notion_conn_status: :ok,
           notion_conn_message: nil
         )}

      {:error, reason} ->
        row_statuses =
          rows
          |> Enum.reduce(%{}, fn row, acc -> Map.put(acc, row.id, :error) end)

        {:noreply,
         assign(socket,
           row_statuses: Map.merge(socket.assigns.row_statuses, row_statuses),
           notion_conn_status: :error,
           notion_conn_message: "Failed to fetch Notion records: " <> inspect(reason)
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <% total_count = length(@statements) %>
      <% filtered_rows = if @hide_exists? do
        Enum.reject(@statements, fn s -> Map.get(@row_statuses, s.id) == :exists end)
      else
        @statements
      end %>
      <% visible_count = length(filtered_rows) %>
      <% hidden_count = total_count - visible_count %>

      <div class="space-y-2">
        <!-- Row 1: Title and primary toggles -->
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <h1 class="text-xl font-semibold">Statement Dump</h1>

          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="toggle_select_all"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @all_selected?, do: "Clear All", else: "Select All"}
            </button>

            <button
              phx-click="toggle_hide_exists"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
            >
              {if @hide_exists?, do: "Show All", else: "Hide Existing"}
            </button>

            <button
              phx-click="clear_row_statuses"
              class="inline-flex items-center px-3 py-2 rounded-md border border-red-300 text-sm bg-white text-red-600 hover:bg-red-50"
            >
              Clear Highlights
            </button>
          </div>
        </div>

        <!-- Row 2: Status badges on left, action buttons on right -->
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
              Selected: {MapSet.size(@selected_ids)}
            </span>

            <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
              Visible: {visible_count}
            </span>

            <span :if={@hide_exists?} class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
              Hidden: {hidden_count}
            </span>

            <span
              :if={@notion_exists_count + @notion_missing_count > 0}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700"
            >
              Exists: {@notion_exists_count}
            </span>

            <span
              :if={@notion_exists_count + @notion_missing_count > 0}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700"
            >
              Missing: {@notion_missing_count}
            </span>

            <span
              :if={@notion_conn_status == :ok}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-700"
            >
              Notion: Connected
            </span>

            <span
              :if={@notion_conn_status == :error}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700"
              title={@notion_conn_message}
            >
              Notion: Failed
            </span>
          </div>

          <div class="flex items-center gap-2 flex-wrap">
            <button
              phx-click="check_notion_connection"
              class="inline-flex items-center px-3 py-2 rounded-md border border-gray-300 text-sm bg-white text-gray-800 hover:bg-gray-50"
              phx-disable-with="Checking..."
            >
              Check Connection
            </button>

            <button
              phx-click="check_notion"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_ids) == 0}
              phx-disable-with="Checking..."
            >
              Check Notion
            </button>

            <button
              phx-click="insert_missing_notion"
              class="inline-flex items-center px-3 py-2 rounded-md border border-transparent text-sm bg-green-600 text-white hover:bg-green-700 disabled:opacity-50"
              disabled={MapSet.size(@selected_ids) == 0}
              phx-disable-with="Inserting..."
            >
              Insert Missing
            </button>
          </div>
        </div>
      </div>

      <ActivityStatementList.list
        id="statement-dump"
        title="All Statements"
        count={length(filtered_rows)}
        rows={filtered_rows}
        expanded={true}
        show_save_controls?={false}
        show_values?={true}
        selectable?={true}
        selected_ids={@selected_ids}
        all_selected?={@all_selected?}
        on_toggle_row_event="toggle_row"
        on_toggle_all_event="toggle_select_all"
        row_statuses={@row_statuses}
      />
    </div>
    """
  end

  # keep helpers after event handlers

  # keep helpers after event handlers

  defp format_conn_error(user_res, db_res) do
    ur =
      case user_res do
        {:ok, _} -> nil
        {:error, reason} -> "user: #{inspect(reason)}"
      end

    dr =
      case db_res do
        {:ok, _} -> nil
        {:error, reason} -> "db: #{inspect(reason)}"
      end

    [ur, dr]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end
end

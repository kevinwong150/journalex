defmodule JournalexWeb.ActivityStatementLive do
  use JournalexWeb, :live_view
  alias Journalex.ActivityStatementParser
  alias Journalex.Activity
  alias JournalexWeb.ActivityStatementSummary
  alias JournalexWeb.ActivityStatementList

  @impl true
  def mount(_params, _session, socket) do
    trades = load_latest_trades()
    # annotate each row with existence flag
    exists_flags = Activity.rows_exist_flags(trades)

    trades =
      trades
      |> Enum.with_index()
      |> Enum.map(fn {row, idx} -> Map.put(row, :exists, Enum.at(exists_flags, idx)) end)

    {summary_by_symbol, summary_total} = summarize_realized_pl(trades)
    period = load_latest_period()

    # Compute selected business days (Mon-Fri) present in trades
    selected_days =
      trades
      |> Enum.map(&date_only(Map.get(&1, :datetime)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&parse_date!/1)
      |> Enum.filter(fn %Date{} = d -> Date.day_of_week(d) in 1..5 end)
      |> length()

    {:ok,
     socket
     |> assign(:activity_data, trades)
     |> assign(:summary_by_symbol, summary_by_symbol)
     |> assign(:summary_total, summary_total)
     |> assign(:selected_days, selected_days)
     |> assign(:statement_period, period)
     |> assign(:summary_expanded, false)
     |> assign(:activity_expanded, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Activity Statement</h1>

        <p class="mt-2 text-gray-600">View your account activity and transaction history</p>

        <%= if @statement_period do %>
          <p class="mt-1 text-sm text-gray-500">
            Statement Date: <span class="font-medium text-gray-700">{@statement_period}</span>
          </p>
        <% end %>
      </div>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
        <!-- Summary: Realized P/L by Symbol -->
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-gray-900">Summary (Realized P/L by Symbol)</h2>

              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-700">
                {length(@summary_by_symbol)}
              </span>

              <button
                phx-click="toggle_summary"
                class="inline-flex items-center px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
                aria-expanded={@summary_expanded}
                aria-controls="summary-table"
              >
                <%= if @summary_expanded do %>
                  Collapse
                <% else %>
                  Expand
                <% end %>
              </button>
            </div>

            <.link
              navigate={~p"/activity_statement/upload"}
              class="inline-flex items-center px-3 py-1 bg-blue-50 text-blue-700 text-xs font-medium rounded-md hover:bg-blue-100"
            >
              Upload New Statement
            </.link>
          </div>
        </div>

        <ActivityStatementSummary.summary_table
          rows={@summary_by_symbol}
          total={@summary_total}
          expanded={@summary_expanded}
          selected_days={@selected_days}
          id="summary-table"
        />

        <ActivityStatementList.list
          id="activity-table"
          title="Recent Activity"
          count={length(@activity_data)}
          rows={@activity_data}
          expanded={@activity_expanded}
          toggle_event="toggle_activity"
          show_save_controls?={true}
          on_save_all?="save_all"
          on_upload_path?={~p"/activity_statement/upload"}
          on_save_row_event="save_row"
          show_values?={true}
        />

        <%= if Enum.empty?(@activity_data) do %>
          <div class="px-6 py-12 text-center">
            <div class="mx-auto w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-4">
              <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                />
              </svg>
            </div>

            <h3 class="text-sm font-medium text-gray-900 mb-2">No activity data available</h3>

            <p class="text-sm text-gray-500 mb-4">
              Upload a CSV file to view your activity statement
            </p>

            <.link
              navigate={~p"/activity_statement/upload"}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700"
            >
              Upload Statement
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp load_latest_trades do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()
    file_path = Path.join(uploads_dir, "latest_activity_statement.csv")

    if File.exists?(file_path) do
      try do
        ActivityStatementParser.parse_trades_file(file_path)
      rescue
        _ -> []
      end
    else
      []
    end
  end

  defp load_latest_period do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()
    file_path = Path.join(uploads_dir, "latest_activity_statement.csv")

    if File.exists?(file_path) do
      try do
        ActivityStatementParser.parse_period_file(file_path)
      rescue
        _ -> nil
      end
    else
      nil
    end
  end

  # Summary helpers
  defp summarize_realized_pl(trades) do
    groups = Enum.group_by(trades, & &1.symbol)

    rows =
      groups
      |> Enum.map(fn {symbol, ts} ->
        sum = ts |> Enum.map(&to_number(&1.realized_pl)) |> Enum.sum()
        # Close trades are those with inferred position_action == "CLOSE"
        closes = Enum.filter(ts, fn r -> build_close(r) == "CLOSE" end)
        close_count = length(closes)
        close_positive_count = closes |> Enum.count(fn r -> to_number(r.realized_pl) > 0.0 end)

        days_traded =
          ts
          |> Enum.map(&date_only(Map.get(&1, :datetime)))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> length()

        %{
          symbol: symbol,
          realized_pl: sum,
          close_count: close_count,
          close_positive_count: close_positive_count,
          days_traded: days_traded
        }
      end)
      |> Enum.sort_by(& &1.symbol)

    total = rows |> Enum.map(& &1.realized_pl) |> Enum.sum()
    {rows, total}
  end

  defp date_only(nil), do: nil
  defp date_only(%DateTime{} = dt), do: Date.to_iso8601(DateTime.to_date(dt))
  defp date_only(%NaiveDateTime{} = ndt), do: Date.to_iso8601(NaiveDateTime.to_date(ndt))

  defp date_only(
         <<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), _::binary>>
       ),
       do: y <> "-" <> m <> "-" <> d

  defp date_only(bin) when is_binary(bin) do
    case String.split(bin) do
      [date | _] -> date_only(date)
      _ -> nil
    end
  end

  defp parse_date!(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>) do
    {:ok, dt} = Date.from_iso8601(y <> "-" <> m <> "-" <> d)
    dt
  end

  defp to_number(nil), do: 0.0
  defp to_number(""), do: 0.0

  defp to_number(val) when is_binary(val) do
    val
    |> String.trim()
    |> String.replace(",", "")
    |> case do
      "" ->
        0.0

      s ->
        case Float.parse(s) do
          {n, _} -> n
          :error -> 0.0
        end
    end
  end

  # Support Decimal values from DB or parser
  defp to_number(%Decimal{} = d) do
    # Convert to float; acceptable for zero/non-zero checks and summary
    Decimal.to_float(d)
  end

  defp to_number(val) when is_number(val), do: val * 1.0

  defp build_close(row) do
    # Prefer existing persisted flag if available; else infer from realized_pl as requested
    cond do
      is_map(row) and Map.get(row, :position_action) in ["build", "close"] ->
        row.position_action |> String.upcase()

      true ->
        n = to_number(Map.get(row, :realized_pl))

        if n == 0 do
          "BUILD"
        else
          "CLOSE"
        end
    end
  end

  @impl true
  def handle_event("save_all", _params, socket) do
    trades = socket.assigns.activity_data || []

    try do
      {:ok, inserted} = Activity.save_activity_rows(trades)
      # refresh exists flags
      flags = Activity.rows_exist_flags(trades)

      updated =
        trades
        |> Enum.with_index()
        |> Enum.map(fn {row, i} -> Map.put(row, :exists, Enum.at(flags, i)) end)

      {:noreply,
       socket
       |> assign(:activity_data, updated)
       |> put_flash(:info, "Saved #{inserted} new rows to DB")}
    rescue
      e ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{Exception.message(e)}")}
    end
  end

  @impl true
  def handle_event("toggle_summary", _params, socket) do
    {:noreply, assign(socket, :summary_expanded, !socket.assigns.summary_expanded)}
  end

  @impl true
  def handle_event("toggle_activity", _params, socket) do
    {:noreply, assign(socket, :activity_expanded, !socket.assigns.activity_expanded)}
  end

  @impl true
  def handle_event("save_row", %{"index" => index_str}, socket) do
    with {idx, _} <- Integer.parse(to_string(index_str)),
         rows when is_list(rows) <- socket.assigns.activity_data,
         row when is_map(row) <- Enum.at(rows, idx) do
      case Activity.save_activity_row(row) do
        {:ok, _} ->
          updated =
            rows
            |> List.update_at(idx, fn r -> Map.put(r, :exists, true) end)

          {:noreply,
           socket
           |> assign(:activity_data, updated)
           |> put_flash(:info, "Row saved")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save row: #{inspect(reason)}")}
      end
    else
      _ -> {:noreply, socket}
    end
  end
end

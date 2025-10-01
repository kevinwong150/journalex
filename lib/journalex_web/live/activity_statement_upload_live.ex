defmodule JournalexWeb.ActivityStatementUploadLive do
  use JournalexWeb, :live_view
  alias Journalex.Activity

  @impl true
  def mount(_params, _session, socket) do
    # Build current month's dates grid with ticks for days having records
    today = Date.utc_today()
    first = %Date{year: today.year, month: today.month, day: 1}
    last = end_of_month(first)

    sd = yyyymmdd(first)
    ed = yyyymmdd(last)

    results =
      case Activity.list_activity_statements_between(sd, ed) do
        {:error, _} -> []
        list when is_list(list) -> list
      end

    date_grid = build_single_month_grid(first, last, results)

    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> assign(:upload_status, nil)
     |> assign(:calendar_month, first)
     |> assign(:date_grid, date_grid)
     |> allow_upload(:csv_file,
       accept: ~w(.csv),
       max_entries: 10,
       auto_upload: true,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :csv_file, fn %{path: path}, entry ->
        # Persist the uploaded file(s) to priv/uploads and parse each one
        case save_and_process_csv(path, entry) do
          {:ok, info} -> {:ok, info}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    case uploaded_files do
      [_file | _] ->
        # Schedule redirect after 3 seconds and start countdown ticks
        Process.send_after(self(), :redirect_to_activity, 3_000)
        Process.send_after(self(), :countdown_tick, 1_000)

        {:noreply,
         socket
         |> assign(:uploaded_files, uploaded_files)
         |> assign(:upload_status, :success)
         |> assign(:redirect_countdown, 3)
         |> put_flash(
           :info,
           "CSV file(s) uploaded and processed successfully! Redirecting in 3s…"
         )}

      [] ->
        {:noreply,
         socket
         |> assign(:upload_status, :error)
         |> put_flash(:error, "Failed to process the uploaded file(s).")}
    end
  end

  # Month navigation from the calendar component (grouped with other handle_event clauses)
  @impl true
  def handle_event("prev_month", _params, socket) do
    case socket.assigns[:calendar_month] do
      %Date{} = cm -> refresh_calendar_month(socket, shift_month(cm, -1))
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_month", _params, socket) do
    case socket.assigns[:calendar_month] do
      %Date{} = cm -> refresh_calendar_month(socket, shift_month(cm, 1))
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("current_month", _params, socket) do
    today = Date.utc_today()
    first = %Date{year: today.year, month: today.month, day: 1}
    refresh_calendar_month(socket, first)
  end

  @impl true
  def handle_info(:redirect_to_activity, socket) do
    {:noreply, push_navigate(socket, to: ~p"/activity_statement")}
  end

  @impl true
  def handle_info(:countdown_tick, socket) do
    case Map.get(socket.assigns, :redirect_countdown) do
      n when is_integer(n) and n > 1 ->
        n1 = n - 1
        Process.send_after(self(), :countdown_tick, 1_000)

        {:noreply,
         socket
         |> assign(:redirect_countdown, n1)
         |> put_flash(
           :info,
           "CSV file(s) uploaded and processed successfully! Redirecting in #{n1}s…"
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp save_and_process_csv(temp_path, entry) do
    try do
      uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()
      File.mkdir_p!(uploads_dir)
      # Build a unique, filesystem-safe destination filename per entry
      timestamp =
        DateTime.utc_now()
        |> Calendar.strftime("%Y%m%dT%H%M%S")

      base_name =
        entry.client_name
        |> to_string()
        |> String.replace(~r/[^A-Za-z0-9._-]/, "_")

      unique_suffix = Integer.to_string(System.unique_integer([:positive]))
      dest_filename = "#{timestamp}-#{unique_suffix}-#{base_name}"
      dest_path = Path.join(uploads_dir, dest_filename)

      File.cp!(temp_path, dest_path)

      content = File.read!(dest_path)
      line_count = content |> String.split("\n", trim: true) |> length()
      file_size = byte_size(content)

      {:ok,
       %{
         path: dest_path,
         name: base_name,
         data: %{total_lines: line_count, file_size: file_size},
         processed_at: DateTime.utc_now()
       }}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <div class="mb-8">
        <div class="flex items-center gap-4 mb-4">
          <.link
            navigate={~p"/activity_statement"}
            class="inline-flex items-center text-sm text-gray-600 hover:text-gray-900"
          >
            <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15 19l-7-7 7-7"
              />
            </svg>
            Back to Activity Statement
          </.link>
        </div>

        <h1 class="text-3xl font-bold text-gray-900">Upload Activity Statement</h1>

        <p class="mt-2 text-gray-600">
          Upload one or more CSV files containing your activity statement data
        </p>

        <%= if assigns[:date_grid] && not Enum.empty?(@date_grid) do %>
          <div class="mt-6">
            <JournalexWeb.MonthGrid.month_grid
              months={@date_grid}
              show_nav={true}
              current_month={@calendar_month}
              reset_event="current_month"
              title="This Month's Activity"
            />
          </div>
        <% end %>
      </div>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg">
        <div class="px-6 py-8">
          <form id="upload-form" phx-submit="save" phx-change="validate">
            <div class="space-y-6">
              <!-- File Upload Area -->
              <div class="space-y-4">
                <label class="block text-sm font-medium text-gray-700">
                  CSV Files
                </label>

                <div
                  class="mt-2 flex justify-center px-6 pt-5 pb-6 border-2 border-gray-300 border-dashed rounded-lg hover:border-gray-400 transition-colors"
                  phx-drop-target={@uploads.csv_file.ref}
                >
                  <div class="space-y-2 text-center">
                    <svg
                      class="mx-auto h-12 w-12 text-gray-400"
                      stroke="currentColor"
                      fill="none"
                      viewBox="0 0 48 48"
                    >
                      <path
                        d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                    </svg>

                    <div class="text-sm text-gray-600">
                      <label
                        for={@uploads.csv_file.ref}
                        class="relative cursor-pointer bg-white rounded-md font-medium text-blue-600 hover:text-blue-500 focus-within:outline-none focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-blue-500"
                      >
                        <span>Upload files</span>
                        <.live_file_input upload={@uploads.csv_file} class="sr-only" />
                      </label>
                      <span class="pl-1">or drag and drop</span>
                    </div>

                    <p class="text-xs text-gray-500">CSV files up to 10MB each (max 10 files)</p>
                  </div>
                </div>
                
    <!-- Upload Progress -->
                <%= for entry <- @uploads.csv_file.entries do %>
                  <div class="bg-gray-50 rounded-lg p-4">
                    <div class="flex items-center justify-between mb-2">
                      <div class="flex items-center">
                        <svg
                          class="w-5 h-5 text-gray-400 mr-2"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                          />
                        </svg>
                        <span class="text-sm font-medium text-gray-900">{entry.client_name}</span>
                      </div>

                      <button
                        type="button"
                        phx-click="cancel-upload"
                        phx-value-ref={entry.ref}
                        class="text-gray-400 hover:text-gray-600"
                      >
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M6 18L18 6M6 6l12 12"
                          />
                        </svg>
                      </button>
                    </div>
                    
    <!-- Progress Bar -->
                    <div class="w-full bg-gray-200 rounded-full h-2">
                      <div
                        class="bg-blue-600 h-2 rounded-full transition-all duration-300"
                        style={"width: #{entry.progress}%"}
                      >
                      </div>
                    </div>

                    <div class="flex justify-between mt-1">
                      <span class="text-xs text-gray-500">{entry.progress}% uploaded</span>
                      <span class="text-xs text-gray-500">
                        {Float.round(entry.client_size / 1024, 1)}KB
                      </span>
                    </div>
                    
    <!-- Upload Errors -->
                    <%= for err <- upload_errors(@uploads.csv_file, entry) do %>
                      <div class="mt-2 text-sm text-red-600">
                        {error_to_string(err)}
                      </div>
                    <% end %>
                  </div>
                <% end %>
                
    <!-- General Upload Errors -->
                <%= for err <- upload_errors(@uploads.csv_file) do %>
                  <div class="text-sm text-red-600">
                    {error_to_string(err)}
                  </div>
                <% end %>
              </div>
              
    <!-- File Requirements -->
              <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <svg
                      class="h-5 w-5 text-blue-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                  </div>

                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-blue-800">CSV File Requirements</h3>

                    <div class="mt-2 text-sm text-blue-700">
                      <ul class="list-disc pl-5 space-y-1">
                        <li>File must be in CSV format</li>

                        <li>Maximum file size: 10MB per file</li>

                        <li>Expected columns: Date, Description, Amount, Type</li>

                        <li>Date format: YYYY-MM-DD</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
              
    <!-- Submit Button -->
              <div class="flex justify-end">
                <button
                  type="submit"
                  disabled={
                    Enum.empty?(@uploads.csv_file.entries) || !upload_complete?(@uploads.csv_file)
                  }
                  class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
                    />
                  </svg>
                  Process Files
                </button>
              </div>
            </div>
          </form>
          
    <!-- Upload Results -->
          <%= if @upload_status == :success and not Enum.empty?(@uploaded_files) do %>
            <div class="mt-8 bg-green-50 border border-green-200 rounded-lg p-4">
              <div class="flex">
                <div class="flex-shrink-0">
                  <svg
                    class="h-5 w-5 text-green-400"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </div>

                <div class="ml-3">
                  <h3 class="text-sm font-medium text-green-800">File(s) Processed Successfully</h3>

                  <%= for file <- @uploaded_files do %>
                    <div class="mt-2 text-sm text-green-700">
                      <p><strong>File name:</strong> {file.name}</p>
                      <p><strong>Total lines:</strong> {file.data.total_lines}</p>

                      <p>
                        <strong>File size:</strong> {Float.round(file.data.file_size / 1024, 1)}KB
                      </p>

                      <p>
                        <strong>Processed at:</strong> {Calendar.strftime(
                          file.processed_at,
                          "%Y-%m-%d %H:%M:%S UTC"
                        )}
                      </p>

                      <div class="mt-3">
                        <.link
                          navigate={~p"/activity_statement"}
                          class="inline-flex items-center px-3 py-1 bg-green-600 text-white text-xs font-medium rounded hover:bg-green-700"
                        >
                          View Activity Statement
                        </.link>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp upload_complete?(upload) do
    Enum.all?(upload.entries, &(&1.progress == 100))
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Too many files selected (max 10)"
  defp error_to_string(:not_accepted), do: "File type not accepted (CSV only)"
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"

  # Helpers copied to render the dates calendar
  defp build_single_month_grid(%Date{} = first, %Date{} = last, statements) do
    present =
      statements
      |> Enum.map(fn s -> s.datetime |> DateTime.to_date() end)
      |> MapSet.new()

    # Sunday-first leading blanks
    dow = Date.day_of_week(first)
    leading = rem(dow, 7)

    month_days = Date.range(first, last) |> Enum.to_list()

    cells =
      List.duplicate(%{date: nil}, leading) ++
        Enum.map(month_days, fn d ->
          %{
            date: d,
            in_range: true,
            has: MapSet.member?(present, d)
          }
        end)

    trailing = rem(7 - rem(length(cells), 7), 7)
    padded = cells ++ List.duplicate(%{date: nil}, trailing)

    [%{label: month_label(first), weeks: Enum.chunk_every(padded, 7)}]
  end

  defp end_of_month(%Date{year: y, month: m}) do
    last_day = :calendar.last_day_of_the_month(y, m)
    Date.new!(y, m, last_day)
  end

  defp yyyymmdd(%Date{year: y, month: m, day: d}) do
    y_str = Integer.to_string(y) |> String.pad_leading(4, "0")
    m_str = Integer.to_string(m) |> String.pad_leading(2, "0")
    d_str = Integer.to_string(d) |> String.pad_leading(2, "0")
    y_str <> m_str <> d_str
  end

  defp month_label(%Date{year: y, month: m}) do
    month_names =
      ~w(January February March April May June July August September October November December)

    name = Enum.at(month_names, m - 1)
    "#{name} #{y}"
  end

  # Month navigation handlers moved above alongside other handle_event clauses

  defp refresh_calendar_month(socket, %Date{} = first) do
    last = end_of_month(first)
    sd = yyyymmdd(first)
    ed = yyyymmdd(last)

    results =
      case Activity.list_activity_statements_between(sd, ed) do
        {:error, _} -> []
        list when is_list(list) -> list
      end

    grid = build_single_month_grid(first, last, results)

    {:noreply,
     socket
     |> assign(:calendar_month, first)
     |> assign(:date_grid, grid)}
  end

  defp shift_month(%Date{year: y, month: m}, delta) when is_integer(delta) do
    total = y * 12 + (m - 1) + delta
    ny = div(total, 12)
    nm = rem(total, 12) + 1
    Date.new!(ny, nm, 1)
  end
end

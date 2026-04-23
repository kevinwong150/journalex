defmodule JournalexWeb.AnalyticsFilterBar do
  use JournalexWeb, :html

  @moduledoc """
  Shared filter bar for analytics LiveViews.

  Emits the following LiveView events (use `handle_event/3` in the parent LiveView):
  - "set_period"      %{"period" => "this_week"|"last_week"|"this_month"|"last_month"|"ytd"|"all"|"month:YYYY-MM"|"week:YYYY-MM-DD"}
  - "toggle_version"  %{"version" => "2"}
  - "filter_dates"    %{"from" => "2026-01-01", "to" => "2026-04-23"}
  - "set_r_mode"      %{"mode" => "r" | "usd" | "both"}
  - "reload"          %{} — manual chart refresh
  """

  attr :versions_available, :list, required: true
  attr :selected_versions, :list, required: true
  attr :from, :string, default: nil
  attr :to, :string, default: nil
  attr :r_mode, :string, default: "r"

  def analytics_filter_bar(assigns) do
    today = Date.utc_today()

    assigns =
      assign(assigns,
        month_options: build_month_options(today),
        week_options: build_week_options(today)
      )

    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-zinc-50 text-sm divide-y divide-zinc-200">
      <!-- Row 1: Quick period presets + month/week pickers -->
      <div class="flex flex-wrap items-center gap-2 px-4 py-2">
        <span class="text-[10px] font-semibold uppercase tracking-wider text-zinc-400">Period:</span>
        <%= for {label, period} <- [
          {"This Week", "this_week"},
          {"Last Week", "last_week"},
          {"This Month", "this_month"},
          {"Last Month", "last_month"},
          {"YTD", "ytd"},
          {"All Time", "all"}
        ] do %>
          <button
            phx-click="set_period"
            phx-value-period={period}
            class="rounded-full px-2.5 py-0.5 font-medium border bg-white text-zinc-700 border-zinc-300 hover:bg-zinc-100"
          >
            <%= label %>
          </button>
        <% end %>
        <span class="text-zinc-300 select-none">|</span>
        <!-- Month picker -->
        <form phx-change="set_period" class="inline-flex">
          <select name="period" class="rounded border border-zinc-300 px-2 py-0.5 bg-white text-zinc-600 cursor-pointer">
            <option value="">Month…</option>
            <%= for {value, label} <- @month_options do %>
              <option value={value}><%= label %></option>
            <% end %>
          </select>
        </form>
        <!-- Week picker -->
        <form phx-change="set_period" class="inline-flex">
          <select name="period" class="rounded border border-zinc-300 px-2 py-0.5 bg-white text-zinc-600 cursor-pointer">
            <option value="">Week…</option>
            <%= for {value, label} <- @week_options do %>
              <option value={value}><%= label %></option>
            <% end %>
          </select>
        </form>
      </div>

      <!-- Row 2: Version + custom date range + R mode + Reload -->
      <div class="flex flex-wrap items-center gap-4 px-4 py-2">
        <!-- Version filter -->
        <div class="flex items-center gap-2">
          <span class="font-semibold text-zinc-500">Version:</span>
          <%= for v <- @versions_available do %>
            <button
              phx-click="toggle_version"
              phx-value-version={v}
              class={"rounded-full px-2.5 py-0.5 font-medium border #{if v in @selected_versions, do: "bg-zinc-900 text-white border-zinc-900", else: "bg-white text-zinc-600 border-zinc-300 hover:bg-zinc-100"}"}
            >
              V<%= v %>
            </button>
          <% end %>
        </div>

        <!-- Custom date range — phx-submit so charts only reload on explicit Apply -->
        <form phx-submit="filter_dates" class="flex items-center gap-2">
          <span class="font-semibold text-zinc-500">From:</span>
          <input
            type="date"
            name="from"
            value={@from}
            class="rounded border border-zinc-300 px-2 py-0.5 text-zinc-900"
          />
          <span class="font-semibold text-zinc-500">To:</span>
          <input
            type="date"
            name="to"
            value={@to}
            class="rounded border border-zinc-300 px-2 py-0.5 text-zinc-900"
          />
          <button type="submit" class="rounded px-2.5 py-0.5 font-medium border bg-white text-zinc-600 border-zinc-300 hover:bg-zinc-100">
            Apply
          </button>
        </form>

        <!-- R / $ / Both toggle -->
        <div class="flex items-center gap-1">
          <%= for {label, mode} <- [{"R", "r"}, {"$", "usd"}, {"Both", "both"}] do %>
            <button
              phx-click="set_r_mode"
              phx-value-mode={mode}
              class={"rounded px-2.5 py-0.5 font-medium border #{if @r_mode == mode, do: "bg-zinc-900 text-white border-zinc-900", else: "bg-white text-zinc-600 border-zinc-300 hover:bg-zinc-100"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>

        <!-- Manual reload -->
        <button
          phx-click="reload"
          class="ml-auto rounded px-2.5 py-0.5 font-medium border bg-white text-zinc-600 border-zinc-300 hover:bg-zinc-100"
          title="Reload charts"
        >
          ↺ Reload
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Option builders (run server-side at render time)
  # ---------------------------------------------------------------------------

  defp build_month_options(today) do
    for i <- 0..17 do
      total = today.year * 12 + today.month - 1 - i
      year = div(total, 12)
      month = rem(total, 12) + 1
      ym = "#{year}-#{String.pad_leading(to_string(month), 2, "0")}"
      label = Calendar.strftime(Date.new!(year, month, 1), "%B %Y")
      {"month:#{ym}", label}
    end
  end

  defp build_week_options(today) do
    this_monday = Date.add(today, -(Date.day_of_week(today) - 1))

    for i <- 0..25 do
      week_start = Date.add(this_monday, -7 * i)
      week_end = Date.add(week_start, 6)
      {_yr, week_num} = :calendar.iso_week_number(Date.to_erl(week_start))
      start_label = Calendar.strftime(week_start, "%b %d")
      end_label = Calendar.strftime(week_end, "%b %d")
      {"week:#{Date.to_iso8601(week_start)}", "W#{week_num} · #{start_label}–#{end_label}"}
    end
  end
end


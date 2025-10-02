defmodule JournalexWeb.TradesLive do
  use JournalexWeb, :live_view
  import Ecto.Query, only: [from: 2]

  alias Journalex.Activity
  alias Journalex.ActivityStatementParser
  alias JournalexWeb.AggregatedTradeList

  @impl true
  def mount(_params, _session, socket) do
    trades = load_all_trades() |> Activity.dedupe_by_datetime_symbol()

    # Only include trades that represent a closed position for aggregation
    close_trades =
      trades
      |> Enum.filter(fn r -> build_close(r) == "CLOSE" end)
      |> Enum.map(&put_aggregated_side/1)

    # Annotate with :exists flags based on what's already persisted
    annotated = annotate_trades_with_exists(close_trades)

    {:ok,
     socket
     |> assign(:close_trades, annotated)
     |> assign(:total, Enum.map(annotated, &to_number(Map.get(&1, :realized_pl))) |> Enum.sum())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Aggregated Trades</h1>

        <div class="mt-2 flex items-center justify-between">
          <p class="text-gray-600">All closed trades across uploaded statements</p>

          <button
            type="button"
            phx-click="save_all_trades"
            class="inline-flex items-center px-3 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
            title="Save all aggregated trades to database"
          >
            Save All Trades
          </button>
        </div>
      </div>

      <div class="bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg p-4">
        <div class="mb-2 flex items-center justify-between">
          <div class="text-sm text-gray-600">
            Total Realized P/L: <span class={pl_class_amount(@total)}>{format_amount(@total)}</span>
          </div>

          <div class="text-xs text-gray-500">
            {length(@close_trades)} trades
          </div>
        </div>

        <AggregatedTradeList.aggregated_trade_list
          id="trades-table"
          items={@close_trades}
          sortable={true}
          default_sort_by={:date}
          default_sort_dir={:desc}
          show_save_controls?={true}
          on_save_row_event="save_trade_row"
        />
      </div>
    </div>
    """
  end

  # Helpers largely mirrored from ActivityStatementUploadResultLive for consistency
  defp load_all_trades do
    uploads_dir = Path.join([:code.priv_dir(:journalex), "uploads"]) |> to_string()

    csv_files =
      case File.ls(uploads_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".csv"))
          |> Enum.map(&Path.join(uploads_dir, &1))

        _ ->
          []
      end

    csv_files
    |> Enum.flat_map(fn path ->
      try do
        ActivityStatementParser.parse_trades_file(path)
      rescue
        _ -> []
      end
    end)
  end

  # Compute the aggregated trade side as the opposite of the close trade side
  defp put_aggregated_side(row) when is_map(row) do
    side =
      case Map.get(row, :side) || Map.get(row, "side") do
        s when is_binary(s) ->
          String.downcase(s)

        _ ->
          q = to_number(Map.get(row, :quantity) || Map.get(row, "quantity") || 0)
          if q < 0, do: "short", else: "long"
      end

    agg = if side == "long", do: "SHORT", else: if(side == "short", do: "LONG", else: "-")
    Map.put(row, :aggregated_side, agg)
  end

  defp build_close(row) do
    # Prefer existing persisted flag if available; else infer from realized_pl as in ActivityStatementUploadResultLive
    cond do
      is_map(row) and Map.get(row, :position_action) in ["build", "close"] ->
        row.position_action |> String.upcase()

      true ->
        n = to_number(Map.get(row, :realized_pl))
        if n == 0, do: "BUILD", else: "CLOSE"
    end
  end

  # Numeric conversions (accept number, Decimal, or string)
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

  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(val) when is_number(val), do: val * 1.0

  # Formatting helpers (duplicated to keep this LiveView self-contained)
  defp pl_class_amount(n) when is_number(n) do
    cond do
      n < 0 -> "text-red-600"
      n > 0 -> "text-green-600"
      true -> "text-gray-900"
    end
  end

  defp format_amount(nil), do: "0.00"
  defp format_amount(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
  defp format_amount(%Decimal{} = d), do: d |> Decimal.to_float() |> format_amount()

  defp format_amount(bin) when is_binary(bin) do
    case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
      {n, _} -> format_amount(n)
      :error -> "0.00"
    end
  end

  # date helpers copied from ActivityStatementUploadResultLive
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

  # Parse ISO or naive datetime coming from button values; fall back to date-only
  defp parse_param_datetime(nil), do: nil

  defp parse_param_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} ->
        DateTime.truncate(dt, :second)

      _ ->
        case NaiveDateTime.from_iso8601(s) do
          {:ok, ndt} ->
            NaiveDateTime.truncate(ndt, :second)

          _ ->
            case date_only(s) do
              <<_::binary-size(10)>> = iso -> NaiveDateTime.new!(parse_date!(iso), ~T[00:00:00])
              _ -> nil
            end
        end
    end
  end

  @impl true
  def handle_event("save_all_trades", _params, socket) do
    items = socket.assigns.close_trades || []
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      items
      |> Enum.map(fn item ->
        %{
          datetime: coerce_item_datetime(item),
          ticker:
            Map.get(item, :symbol) || Map.get(item, :ticker) || Map.get(item, :underlying) || "-",
          aggregated_side: Map.get(item, :aggregated_side) || "-",
          result: if(to_number(Map.get(item, :realized_pl)) > 0.0, do: "WIN", else: "LOSE"),
          realized_pl: to_number(Map.get(item, :realized_pl)) |> Decimal.from_float(),
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      {count, _} = Journalex.Repo.insert_all("trades", rows, on_conflict: :nothing)

      # Re-annotate from DB so status reflects actual persisted state (including duplicates)
      updated = annotate_trades_with_exists(items)

      {:noreply,
       socket
       |> assign(:close_trades, updated)
       |> put_flash(:info, "Saved #{count} aggregated trade records")}
    rescue
      e ->
        {:noreply,
         socket |> put_flash(:error, "Failed to save aggregated trades: #{Exception.message(e)}")}
    end
  end

  @impl true
  def handle_event("save_trade_row", params, socket) do
    # Prefer robust values emitted by the Save button to avoid index/order issues after client sorting
    dt_param = Map.get(params, "datetime")
    ticker = Map.get(params, "ticker")
    side = Map.get(params, "side")
    pl_param = Map.get(params, "pl")

    {attrs, match_key} =
      if dt_param || ticker || side || pl_param do
        pl =
          case Float.parse(to_string(pl_param || "0")) do
            {n, _} -> n
            _ -> 0.0
          end

        dt = parse_param_datetime(dt_param)

        {%{
           datetime: dt || DateTime.utc_now() |> DateTime.truncate(:second),
           ticker: ticker || "-",
           aggregated_side: side || "-",
           result: if(pl > 0.0, do: "WIN", else: "LOSE"),
           realized_pl: pl
         }, {:values, %{date: date_only(dt_param), ticker: ticker, side: side, pl: pl}}}
      else
        # Backward compatibility: fall back to index when values are not present
        case Integer.parse(to_string(Map.get(params, "index", "-1"))) do
          {i, _} ->
            case Enum.at(socket.assigns.close_trades, i) do
              nil ->
                {nil, :none}

              item ->
                {%{
                   datetime: coerce_item_datetime(item),
                   ticker:
                     Map.get(item, :symbol) || Map.get(item, :ticker) ||
                       Map.get(item, :underlying) || "-",
                   aggregated_side: Map.get(item, :aggregated_side) || "-",
                   result:
                     if(to_number(Map.get(item, :realized_pl)) > 0.0, do: "WIN", else: "LOSE"),
                   realized_pl: to_number(Map.get(item, :realized_pl))
                 }, {:index, i}}
            end

          :error ->
            {nil, :none}
        end
      end

    case attrs do
      nil ->
        {:noreply, socket}

      attrs ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        row =
          Map.merge(attrs, %{
            realized_pl: Decimal.from_float(attrs.realized_pl),
            inserted_at: now,
            updated_at: now
          })

        try do
          {count, _} = Journalex.Repo.insert_all("trades", [row], on_conflict: :nothing)

          updated =
            case match_key do
              {:index, i} when is_integer(i) and i >= 0 ->
                List.update_at(socket.assigns.close_trades, i, &Map.put(&1, :exists, true))

              {:values, %{date: d, ticker: t, side: s, pl: p}} ->
                Enum.map(socket.assigns.close_trades, fn it ->
                  item_date = date_only(Map.get(it, :datetime))

                  item_ticker =
                    Map.get(it, :symbol) || Map.get(it, :ticker) || Map.get(it, :underlying)

                  item_side = Map.get(it, :aggregated_side)
                  item_pl = to_number(Map.get(it, :realized_pl))

                  if item_date == d and item_ticker == t and item_side == s and item_pl == p do
                    Map.put(it, :exists, true)
                  else
                    it
                  end
                end)

              _ ->
                socket.assigns.close_trades
            end

          {:noreply,
           socket
           |> assign(:close_trades, updated)
           |> put_flash(:info, if(count > 0, do: "Saved", else: "Already exists"))}
        rescue
          e ->
            {:noreply, socket |> put_flash(:error, "Failed to save row: #{Exception.message(e)}")}
        end
    end
  end

  # Build a NaiveDateTime/DateTime from item; if only a date is present default to midnight
  defp coerce_item_datetime(item) do
    case Map.get(item, :datetime) || Map.get(item, "datetime") do
      %DateTime{} = dt ->
        dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second) |> DateTime.to_naive()

      %NaiveDateTime{} = ndt ->
        NaiveDateTime.truncate(ndt, :second)

      s when is_binary(s) ->
        case DateTime.from_iso8601(s) do
          {:ok, dt, _} ->
            dt
            |> DateTime.shift_zone!("Etc/UTC")
            |> DateTime.truncate(:second)
            |> DateTime.to_naive()

          _ ->
            case NaiveDateTime.from_iso8601(s) do
              {:ok, ndt} ->
                NaiveDateTime.truncate(ndt, :second)

              _ ->
                case date_only(s) do
                  <<_::binary-size(10)>> = iso ->
                    d = parse_date!(iso)
                    NaiveDateTime.new!(d, ~T[00:00:00])

                  _ ->
                    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
                end
            end
        end

      nil ->
        case Map.get(item, :date) || Map.get(item, "date") do
          %Date{} = d ->
            NaiveDateTime.new!(d, ~T[00:00:00])

          <<_::binary-size(10)>> = iso ->
            d = parse_date!(iso)
            NaiveDateTime.new!(d, ~T[00:00:00])

          _ ->
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
        end

      _ ->
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
    end
  end

  # ===== Existence annotation against persisted DB trades =====
  defp annotate_trades_with_exists(items) when is_list(items) do
    keyset = persisted_trades_keyset(items)

    Enum.map(items, fn item ->
      date =
        date_only(
          Map.get(item, :datetime) || Map.get(item, "datetime") || Map.get(item, :date) ||
            Map.get(item, "date")
        )

      ticker = Map.get(item, :symbol) || Map.get(item, :ticker) || Map.get(item, :underlying)
      side = Map.get(item, :aggregated_side) || Map.get(item, "aggregated_side")
      pl = Map.get(item, :realized_pl)
      key = {date, ticker, side, round2(to_number(pl))}

      if MapSet.member?(keyset, key),
        do: Map.put(item, :exists, true),
        else: Map.put(item, :exists, false)
    end)
  end

  defp annotate_trades_with_exists(other), do: other

  defp persisted_trades_keyset(items) when is_list(items) do
    dates =
      items
      |> Enum.map(fn it ->
        date_only(
          Map.get(it, :datetime) || Map.get(it, "datetime") || Map.get(it, :date) ||
            Map.get(it, "date")
        )
      end)
      |> Enum.reject(&is_nil/1)

    tickers =
      items
      |> Enum.map(fn it ->
        Map.get(it, :symbol) || Map.get(it, :ticker) || Map.get(it, :underlying)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case dates do
      [] ->
        MapSet.new()

      _ ->
        min_d = dates |> Enum.map(&parse_date!/1) |> Enum.min(Date)
        max_d = dates |> Enum.map(&parse_date!/1) |> Enum.max(Date)

        start_dt = DateTime.new!(min_d, ~T[00:00:00], "Etc/UTC")
        end_dt = DateTime.new!(max_d, ~T[23:59:59], "Etc/UTC")

        q =
          from t in "trades",
            where: t.datetime >= ^start_dt and t.datetime <= ^end_dt,
            where: t.ticker in ^tickers,
            select: {fragment("date(?)", t.datetime), t.ticker, t.aggregated_side, t.realized_pl}

        Journalex.Repo.all(q)
        |> Enum.map(fn {date, ticker, side, pl} ->
          {Date.to_iso8601(date), ticker, side, round2(to_number(pl))}
        end)
        |> MapSet.new()
    end
  end

  defp round2(nil), do: 0.0
  defp round2(n) when is_number(n), do: Float.round(n * 1.0, 2)
  defp round2(%Decimal{} = d), do: d |> Decimal.to_float() |> round2()

  defp round2(val) when is_binary(val) do
    case Float.parse(String.replace(val, ",", "") |> String.trim()) do
      {n, _} -> round2(n)
      :error -> 0.0
    end
  end
end

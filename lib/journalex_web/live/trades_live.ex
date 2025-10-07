defmodule JournalexWeb.TradesLive do
  use JournalexWeb, :live_view
  import Ecto.Query, only: [from: 2]

  alias Journalex.Repo
  alias Journalex.Trades.Trade
  alias JournalexWeb.AggregatedTradeList

  @impl true
  def mount(_params, _session, socket) do
    # Fetch all trades from the database
    trades = load_all_trades()

    total =
      trades
      |> Enum.map(&to_number(Map.get(&1, :realized_pl)))
      |> Enum.sum()

    {:ok,
     socket
     |> assign(:close_trades, trades)
     |> assign(:total, total)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">All Trades</h1>

        <div class="mt-2">
          <p class="text-gray-600">All saved trades from the database</p>
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
          default_sort_by={:datetime}
          default_sort_dir={:desc}
          show_save_controls?={false}
        />
      </div>
    </div>
    """
  end

  # Load all trades from the database
  defp load_all_trades do
    Repo.all(from t in Trade, order_by: [desc: t.datetime])
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

  # Formatting helpers
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
end

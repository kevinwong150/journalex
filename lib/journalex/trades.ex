defmodule Journalex.Trades do
  @moduledoc """
  Context for working with trades data.
  """
  import Ecto.Query, warn: false
  alias Journalex.{Repo, Trades.Trade, Trades.ActionChainBuilder}

  @doc """
  List all trades ordered by datetime descending.
  """
  def list_all_trades do
    from(t in Trade, order_by: [desc: t.datetime])
    |> Repo.all()
  end

  @doc """
  List trades between two dates, inclusive.

  Accepts start_date and end_date as Date structs or strings formatted as "yyyymmdd".
  Returns trades ordered ascending by datetime by default; can override with :order option.
  """
  def list_trades_between(start_date, end_date, opts \\ []) do
    with {:ok, start_dt} <- normalize_date_start(start_date),
         {:ok, end_dt} <- normalize_date_end(end_date) do
      order = Keyword.get(opts, :order, :asc)

      order_by_expr =
        case order do
          :desc -> [desc: :datetime]
          _ -> [asc: :datetime]
        end

      from(t in Trade,
        where: t.datetime >= ^start_dt and t.datetime <= ^end_dt,
        order_by: ^order_by_expr
      )
      |> Repo.all()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build an action chain for a single aggregated trade item.

  Delegates to Journalex.Trades.ActionChainBuilder.
  """
  def build_action_chain(close_trade_item, opts \\ []) do
    ActionChainBuilder.build_action_chain(close_trade_item, opts)
  end

  @doc """
  Build action chains for multiple aggregated trade items in batch.

  Delegates to Journalex.Trades.ActionChainBuilder.
  """
  def build_action_chains_batch(trade_items) do
    ActionChainBuilder.build_action_chains_batch(trade_items)
  end

  @doc """
  Update a trade with new attributes.
  """
  def update_trade(%Trade{} = trade, attrs) do
    trade
    |> Trade.changeset(attrs)
    |> Repo.update()
  end

  # Normalize inputs like %Date{} or "yyyymmdd" to DateTime bounds
  defp normalize_date_start(%Date{} = d), do: {:ok, DateTime.new!(d, ~T[00:00:00], "Etc/UTC")}

  defp normalize_date_start(%NaiveDateTime{} = ndt),
    do: {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}

  defp normalize_date_start(%DateTime{} = dt), do: {:ok, dt}

  defp normalize_date_start(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>> = _str) do
    case Date.from_iso8601(y <> "-" <> m <> "-" <> d) do
      {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
      _ -> {:error, :invalid_start_date}
    end
  end

  defp normalize_date_start(_), do: {:error, :invalid_start_date}

  defp normalize_date_end(%Date{} = d),
    do: {:ok, DateTime.new!(d, ~T[23:59:59.999999], "Etc/UTC")}

  defp normalize_date_end(%NaiveDateTime{} = ndt), do: {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
  defp normalize_date_end(%DateTime{} = dt), do: {:ok, dt}

  defp normalize_date_end(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>> = _str) do
    case Date.from_iso8601(y <> "-" <> m <> "-" <> d) do
      {:ok, date} -> {:ok, DateTime.new!(date, ~T[23:59:59.999999], "Etc/UTC")}
      _ -> {:error, :invalid_end_date}
    end
  end

  defp normalize_date_end(_), do: {:error, :invalid_end_date}
end

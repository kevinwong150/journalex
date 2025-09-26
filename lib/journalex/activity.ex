defmodule Journalex.Activity do
  @moduledoc """
  Context for working with activity statements data.
  """
  import Ecto.Query, warn: false
  alias Journalex.{Repo, ActivityStatement}

  @doc """
  Bulk insert a list of parsed trade maps into activity_statements.

  Accepts rows shaped like those returned by ActivityStatementParser.parse_trades_file/1.
  """
  def save_activity_rows(rows) when is_list(rows) do
    rows
    |> Enum.map(&to_attrs/1)
    |> Enum.reject(&is_nil(&1.datetime))
    |> Enum.chunk_every(500)
    |> Enum.map(fn chunk ->
      Repo.insert_all(ActivityStatement, chunk, on_conflict: :nothing)
    end)
  end

  defp to_attrs(row) when is_map(row) do
    %{
      datetime: parse_datetime(Map.get(row, :datetime) || Map.get(row, "datetime")),
      side: infer_side(Map.get(row, :quantity) || Map.get(row, "quantity")),
      symbol: get_row(row, :symbol),
      asset_category: get_row(row, :asset_category),
      currency: get_row(row, :currency),
      quantity: to_decimal(get_row(row, :quantity)),
      trade_price: to_decimal(get_row(row, :trade_price)),
      proceeds: to_decimal(get_row(row, :proceeds)),
      comm_fee: to_decimal(get_row(row, :comm_fee)),
      realized_pl: to_decimal(get_row(row, :realized_pl)),
      inserted_at: now_usec(),
      updated_at: now_usec()
    }
  end

  defp get_row(row, key), do: Map.get(row, key) || Map.get(row, to_string(key))

  defp infer_side(qty) do
    case to_number(qty) do
      n when is_number(n) and n < 0 -> "sell"
      _ -> "buy"
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(
         <<year::binary-size(4), "-", mon::binary-size(2), "-", day::binary-size(2), ", ",
           rest::binary>>
       ) do
    case NaiveDateTime.from_iso8601(year <> "-" <> mon <> "-" <> day <> " " <> rest) do
      {:ok, ndt} ->
        ndt
        |> DateTime.from_naive!("Etc/UTC")
        |> ensure_usec()

      _ ->
        nil
    end
  end

  defp parse_datetime(str) when is_binary(str) do
    with {:ok, dt, _} <- DateTime.from_iso8601(str) do
      dt |> ensure_usec()
    else
      _ -> nil
    end
  end

  defp ensure_usec(%DateTime{microsecond: {usec, _}} = dt),
    do: %DateTime{dt | microsecond: {usec, 6}}

  defp ensure_usec(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> ensure_usec()

  defp ensure_usec(other), do: other

  defp now_usec, do: DateTime.utc_now() |> ensure_usec()

  defp to_decimal(nil), do: nil
  defp to_decimal(""), do: nil

  defp to_decimal(val) when is_binary(val) do
    val
    |> String.trim()
    |> String.replace(",", "")
    |> Decimal.new()
  rescue
    _ -> nil
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n) or is_float(n), do: Decimal.from_float(n * 1.0)

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

  defp to_number(val) when is_number(val), do: val * 1.0
end

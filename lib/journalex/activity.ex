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
    attrs =
      rows
      |> Enum.map(&to_attrs/1)
      |> Enum.reject(&is_nil(&1.datetime))

    # Filter out rows that already exist by normalized key
    existing = existing_key_set_for(attrs)

    new_attrs =
      attrs
      |> Enum.reject(fn a -> MapSet.member?(existing, key_from_attrs(a)) end)

    inserted =
      new_attrs
      |> Enum.chunk_every(500)
      |> Enum.map(fn chunk -> Repo.insert_all(ActivityStatement, chunk) end)

    {:ok, inserted |> Enum.map(fn {n, _} -> n end) |> Enum.sum()}
  end

  @doc """
  Save a single row. Returns {:ok, struct} or {:error, reason}.

  Inserts if not exists; if duplicate based on natural key, returns {:ok, :exists}.
  """
  def save_activity_row(row) when is_map(row) do
    attrs = to_attrs(row)

    if is_nil(attrs.datetime) do
      {:error, :invalid_datetime}
    else
      if row_exists_attrs?(attrs) do
        {:ok, :exists}
      else
        case Repo.insert(struct(ActivityStatement, attrs)) do
          {:ok, %ActivityStatement{} = struct} -> {:ok, struct}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  For a list of parsed rows, returns a list of booleans indicating if each row exists.
  """
  def rows_exist_flags(rows) when is_list(rows) do
    attrs = rows |> Enum.map(&to_attrs/1)
    existing_key_set = existing_key_set_for(attrs)

    Enum.map(attrs, fn a ->
      if is_nil(a.datetime) or is_nil(a.quantity) or is_nil(a.trade_price) do
        false
      else
        MapSet.member?(existing_key_set, key_from_attrs(a))
      end
    end)
  end

  defp row_exists_attrs?(attrs) do
    # Fetch candidates by datetime/symbol/side, then compare with normalized decimal keys
    q =
      from s in ActivityStatement,
        where:
          s.symbol == ^attrs.symbol and s.side == ^attrs.side and s.datetime == ^attrs.datetime,
        select: {s.datetime, s.symbol, s.side, s.quantity, s.trade_price}

    candidates = Repo.all(q)
    target = key_from_attrs(attrs)

    candidates
    |> Enum.map(&key_from_db_row/1)
    |> Enum.any?(&(&1 == target))
  end

  # Helpers to build normalized comparable keys
  defp key_from_db_row({datetime, symbol, side, qty, px}) do
    {dt_to_key(datetime), symbol, side, dec_to_key(qty, 8), dec_to_key(px, 8)}
  end

  defp key_from_attrs(%{datetime: dt, symbol: sym, side: side, quantity: qty, trade_price: px}) do
    {dt_to_key(dt), sym, side, dec_to_key(qty, 8), dec_to_key(px, 8)}
  end

  defp dt_to_key(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)

  defp dt_to_key(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

  defp dt_to_key(nil), do: nil

  defp dec_to_key(nil, _scale), do: ""

  defp dec_to_key(%Decimal{} = d, scale) do
    d
    |> Decimal.round(scale)
    |> Decimal.to_string(:normal)
    |> to_fixed_scale(scale)
  end

  defp to_fixed_scale(str, scale) when is_binary(str) do
    case String.split(str, ".", parts: 2) do
      [int] ->
        int <> "." <> String.duplicate("0", scale)

      [int, frac] ->
        padded = frac |> String.pad_trailing(scale, "0") |> String.slice(0, scale)
        int <> "." <> padded
    end
  end

  # Build existing key set for a list of prepared attrs
  defp existing_key_set_for(attrs) do
    groups =
      attrs
      |> Enum.reject(&is_nil(&1.datetime))
      |> Enum.group_by(fn a -> {a.datetime, a.symbol, a.side} end)

    case Map.keys(groups) do
      [] ->
        MapSet.new()

      keys ->
        dyn =
          Enum.reduce(keys, dynamic(false), fn {dt, sym, side}, dyn ->
            dynamic([s], ^dyn or (s.datetime == ^dt and s.symbol == ^sym and s.side == ^side))
          end)

        from(s in ActivityStatement,
          where: ^dyn,
          select: {s.datetime, s.symbol, s.side, s.quantity, s.trade_price}
        )
        |> Repo.all()
        |> Enum.map(&key_from_db_row/1)
        |> MapSet.new()
    end
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

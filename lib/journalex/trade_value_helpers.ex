defmodule Journalex.TradeValueHelpers do
  @moduledoc """
  Shared pure helper functions for converting, parsing, and formatting
  trade-related values (numbers, dates, datetimes, decimals).

  These helpers are used across LiveViews and components.
  Import this module where needed:

      import Journalex.TradeValueHelpers
  """

  @default_decimal_scale 2

  @doc """
  Convert various value types to float.
  Returns 0.0 for nil, empty string, or unparseable values.
  """
  def to_number(nil), do: 0.0
  def to_number(""), do: 0.0

  def to_number(val) when is_binary(val) do
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

  def to_number(%Decimal{} = d), do: Decimal.to_float(d)
  def to_number(val) when is_number(val), do: val * 1.0

  @doc """
  Convert a value to a Decimal, rounded to the given scale (default 2).
  """
  def decimal_from_value(val, scale \\ @default_decimal_scale)
  def decimal_from_value(nil, _scale), do: Decimal.new("0")
  def decimal_from_value(%Decimal{} = d, scale), do: Decimal.round(d, scale)

  def decimal_from_value(val, scale) when is_integer(val),
    do: val |> Decimal.new() |> Decimal.round(scale)

  def decimal_from_value(val, scale) when is_float(val) do
    val |> Decimal.from_float() |> Decimal.round(scale)
  end

  def decimal_from_value(val, scale) when is_binary(val) do
    cleaned = val |> String.trim() |> String.replace(",", "")

    if cleaned == "" do
      Decimal.new("0")
    else
      case Decimal.parse(cleaned) do
        {decimal, _} -> Decimal.round(decimal, scale)
        :error -> Decimal.new("0")
      end
    end
  end

  def decimal_from_value(_, _scale), do: Decimal.new("0")

  @doc """
  Round a numeric value to 2 decimal places.
  """
  def round2(nil), do: 0.0
  def round2(n) when is_number(n), do: Float.round(n * 1.0, 2)
  def round2(%Decimal{} = d), do: d |> Decimal.to_float() |> round2()

  def round2(val) when is_binary(val) do
    case Float.parse(val |> String.replace(",", "") |> String.trim()) do
      {n, _} -> round2(n)
      :error -> 0.0
    end
  end

  @doc """
  Extract ISO date string (YYYY-MM-DD) from various datetime types.
  """
  def date_only(nil), do: nil
  def date_only(%DateTime{} = dt), do: Date.to_iso8601(DateTime.to_date(dt))
  def date_only(%NaiveDateTime{} = ndt), do: Date.to_iso8601(NaiveDateTime.to_date(ndt))

  def date_only(
        <<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), _::binary>>
      ),
      do: y <> "-" <> m <> "-" <> d

  def date_only(bin) when is_binary(bin) do
    case String.split(bin) do
      [date | _] when date != bin -> date_only(date)
      _ -> nil
    end
  end

  @doc """
  Parse an ISO date string (YYYY-MM-DD) into a Date struct.
  Raises on invalid input.
  """
  def parse_date!(<<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2)>>) do
    {:ok, dt} = Date.from_iso8601(y <> "-" <> m <> "-" <> d)
    dt
  end

  @doc """
  Returns true if the given Date is a weekday (Mon–Fri).
  """
  def weekday?(%Date{} = d), do: Date.day_of_week(d) in 1..5

  @doc """
  Parse an event parameter string into a DateTime or NaiveDateTime.
  Returns nil if unparseable.
  """
  def parse_param_datetime(nil), do: nil

  def parse_param_datetime(s) when is_binary(s) do
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

  @doc """
  Coerce an item's :datetime or :date field into a NaiveDateTime.
  Falls back to UTC now if nothing is parseable.
  """
  def coerce_item_datetime(item) do
    case Map.get(item, :datetime) || Map.get(item, "datetime") do
      %DateTime{} = dt ->
        dt
        |> DateTime.shift_zone!("Etc/UTC")
        |> DateTime.truncate(:second)
        |> DateTime.to_naive()

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

  @doc """
  Extract numeric quantity from a map with various key/value formats.
  """
  def extract_quantity_value(item) do
    qty = Map.get(item, :quantity) || Map.get(item, "quantity")

    cond do
      is_number(qty) ->
        qty

      is_struct(qty, Decimal) ->
        Decimal.to_float(qty)

      is_binary(qty) ->
        case Float.parse(qty) do
          {n, _} -> n
          :error -> 0.0
        end

      true ->
        0.0
    end
  end

  @doc """
  Safely format a DateTime/NaiveDateTime or string for display.
  """
  def format_datetime_for_display(%DateTime{} = dt), do: DateTime.to_string(dt)

  def format_datetime_for_display(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_string()
  end

  def format_datetime_for_display(s) when is_binary(s), do: s
  def format_datetime_for_display(other), do: inspect(other)
end

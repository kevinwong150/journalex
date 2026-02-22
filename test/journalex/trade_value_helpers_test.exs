defmodule Journalex.TradeValueHelpersTest do
  use ExUnit.Case, async: true

  import Journalex.TradeValueHelpers

  # ── to_number/1 ──

  describe "to_number/1" do
    test "nil → 0.0" do
      assert to_number(nil) == 0.0
    end

    test "empty string → 0.0" do
      assert to_number("") == 0.0
    end

    test "whitespace-only string → 0.0" do
      assert to_number("   ") == 0.0
    end

    test "integer → float" do
      assert to_number(42) == 42.0
    end

    test "float passes through" do
      assert to_number(3.14) == 3.14
    end

    test "numeric string" do
      assert to_number("123.45") == 123.45
    end

    test "string with commas" do
      assert to_number("1,234.56") == 1234.56
    end

    test "negative string" do
      assert to_number("-8") == -8.0
    end

    test "Decimal struct" do
      assert to_number(Decimal.new("99.9")) == 99.9
    end

    test "unparseable string → 0.0" do
      assert to_number("abc") == 0.0
    end
  end

  # ── decimal_from_value/1,2 ──

  describe "decimal_from_value/1" do
    test "nil → Decimal 0" do
      assert Decimal.equal?(decimal_from_value(nil), Decimal.new("0"))
    end

    test "integer" do
      assert Decimal.equal?(decimal_from_value(42), Decimal.new("42"))
    end

    test "float rounds to scale 2" do
      result = decimal_from_value(3.14159)
      assert Decimal.equal?(result, Decimal.new("3.14"))
    end

    test "string with commas" do
      result = decimal_from_value("1,234.567")
      assert Decimal.equal?(result, Decimal.new("1234.57"))
    end

    test "empty string → 0" do
      assert Decimal.equal?(decimal_from_value(""), Decimal.new("0"))
    end

    test "Decimal passes through (rounded)" do
      d = Decimal.new("21.945126")
      result = decimal_from_value(d)
      assert Decimal.equal?(result, Decimal.new("21.95"))
    end

    test "custom scale" do
      result = decimal_from_value(3.14159, 4)
      assert Decimal.equal?(result, Decimal.new("3.1416"))
    end

    test "unparseable → 0" do
      assert Decimal.equal?(decimal_from_value("abc"), Decimal.new("0"))
    end

    test "other types → 0" do
      assert Decimal.equal?(decimal_from_value(:atom), Decimal.new("0"))
    end
  end

  # ── round2/1 ──

  describe "round2/1" do
    test "nil → 0.0" do
      assert round2(nil) == 0.0
    end

    test "float rounds to 2 decimals" do
      assert round2(3.14159) == 3.14
    end

    test "integer becomes float" do
      assert round2(5) == 5.0
    end

    test "Decimal" do
      assert round2(Decimal.new("21.945126")) == 21.95
    end

    test "string with comma" do
      assert round2("1,234.567") == 1234.57
    end

    test "unparseable string → 0.0" do
      assert round2("nope") == 0.0
    end
  end

  # ── date_only/1 ──

  describe "date_only/1" do
    test "nil → nil" do
      assert date_only(nil) == nil
    end

    test "DateTime" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-02-04T12:20:32Z")
      assert date_only(dt) == "2026-02-04"
    end

    test "NaiveDateTime" do
      ndt = ~N[2026-02-04 12:20:32]
      assert date_only(ndt) == "2026-02-04"
    end

    test "ISO datetime string" do
      assert date_only("2026-02-04 12:20:32") == "2026-02-04"
    end

    test "ISO date string" do
      assert date_only("2026-02-04") == "2026-02-04"
    end

    test "garbage string → nil" do
      assert date_only("not-a-date") == nil
    end
  end

  # ── parse_date!/1 ──

  describe "parse_date!/1" do
    test "valid ISO date" do
      assert parse_date!("2026-02-04") == ~D[2026-02-04]
    end

    test "invalid date raises" do
      assert_raise FunctionClauseError, fn -> parse_date!("not-valid") end
    end
  end

  # ── weekday?/1 ──

  describe "weekday?/1" do
    test "Monday is a weekday" do
      assert weekday?(~D[2026-02-09]) == true
    end

    test "Saturday is not a weekday" do
      assert weekday?(~D[2026-02-07]) == false
    end

    test "Sunday is not a weekday" do
      assert weekday?(~D[2026-02-08]) == false
    end
  end

  # ── parse_param_datetime/1 ──

  describe "parse_param_datetime/1" do
    test "nil → nil" do
      assert parse_param_datetime(nil) == nil
    end

    test "ISO 8601 with timezone" do
      result = parse_param_datetime("2026-02-04T12:20:32Z")
      assert %DateTime{} = result
      assert result.hour == 12
    end

    test "NaiveDateTime string" do
      result = parse_param_datetime("2026-02-04 12:20:32")
      assert %NaiveDateTime{} = result
      assert result.hour == 12
    end

    test "date-only string becomes midnight NaiveDateTime" do
      result = parse_param_datetime("2026-02-04")
      assert %NaiveDateTime{} = result
      assert result.hour == 0
      assert result.minute == 0
    end

    test "garbage string → nil" do
      assert parse_param_datetime("xyz") == nil
    end
  end

  # ── coerce_item_datetime/1 ──

  describe "coerce_item_datetime/1" do
    test "DateTime field → NaiveDateTime" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-02-04T12:20:32Z")
      result = coerce_item_datetime(%{datetime: dt})
      assert %NaiveDateTime{} = result
      assert result.hour == 12
    end

    test "NaiveDateTime field passes through" do
      ndt = ~N[2026-02-04 12:20:32]
      result = coerce_item_datetime(%{datetime: ndt})
      assert result == ndt
    end

    test "string datetime field" do
      result = coerce_item_datetime(%{datetime: "2026-02-04 12:20:32"})
      assert %NaiveDateTime{} = result
      assert result == ~N[2026-02-04 12:20:32]
    end

    test "string key works too" do
      result = coerce_item_datetime(%{"datetime" => "2026-02-04 12:20:32"})
      assert result == ~N[2026-02-04 12:20:32]
    end

    test "falls back to :date field" do
      result = coerce_item_datetime(%{date: ~D[2026-02-04]})
      assert result == ~N[2026-02-04 00:00:00]
    end

    test "no datetime or date → defaults to now" do
      result = coerce_item_datetime(%{})
      assert %NaiveDateTime{} = result
    end
  end

  # ── extract_quantity_value/1 ──

  describe "extract_quantity_value/1" do
    test "integer quantity" do
      assert extract_quantity_value(%{quantity: 8}) == 8
    end

    test "float quantity" do
      assert extract_quantity_value(%{quantity: -8.0}) == -8.0
    end

    test "Decimal quantity" do
      assert extract_quantity_value(%{quantity: Decimal.new("-8")}) == -8.0
    end

    test "string quantity" do
      assert extract_quantity_value(%{quantity: "-8"}) == -8.0
    end

    test "missing quantity → 0.0" do
      assert extract_quantity_value(%{}) == 0.0
    end

    test "string key works" do
      assert extract_quantity_value(%{"quantity" => "60"}) == 60.0
    end
  end

  # ── format_datetime_for_display/1 ──

  describe "format_datetime_for_display/1" do
    test "DateTime" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-02-04T12:20:32Z")
      result = format_datetime_for_display(dt)
      assert is_binary(result)
      assert String.contains?(result, "2026-02-04")
    end

    test "NaiveDateTime" do
      result = format_datetime_for_display(~N[2026-02-04 12:20:32])
      assert is_binary(result)
      assert String.contains?(result, "2026-02-04")
    end

    test "string passes through" do
      assert format_datetime_for_display("hello") == "hello"
    end

    test "other types → inspect" do
      assert format_datetime_for_display(42) == "42"
    end
  end
end

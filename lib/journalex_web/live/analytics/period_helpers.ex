defmodule JournalexWeb.Analytics.PeriodHelpers do
  @moduledoc """
  Shared date-range computation for analytics period presets.
  Returns `{from_iso_string | nil, to_iso_string | nil}`.
  """

  def period_to_dates("this_week") do
    today = Date.utc_today()
    monday = Date.add(today, -(Date.day_of_week(today) - 1))
    {Date.to_iso8601(monday), Date.to_iso8601(today)}
  end

  def period_to_dates("last_week") do
    today = Date.utc_today()
    last_monday = Date.add(today, -(Date.day_of_week(today) - 1) - 7)
    last_sunday = Date.add(last_monday, 6)
    {Date.to_iso8601(last_monday), Date.to_iso8601(last_sunday)}
  end

  def period_to_dates("this_month") do
    today = Date.utc_today()
    first = Date.new!(today.year, today.month, 1)
    {Date.to_iso8601(first), Date.to_iso8601(today)}
  end

  def period_to_dates("last_month") do
    today = Date.utc_today()
    first_this = Date.new!(today.year, today.month, 1)
    last_of_prev = Date.add(first_this, -1)
    first_of_prev = Date.new!(last_of_prev.year, last_of_prev.month, 1)
    {Date.to_iso8601(first_of_prev), Date.to_iso8601(last_of_prev)}
  end

  def period_to_dates("ytd") do
    today = Date.utc_today()
    first = Date.new!(today.year, 1, 1)
    {Date.to_iso8601(first), Date.to_iso8601(today)}
  end

  def period_to_dates("all") do
    {nil, nil}
  end

  def period_to_dates("month:" <> ym) do
    [year_str, month_str] = String.split(ym, "-")
    year = String.to_integer(year_str)
    month = String.to_integer(month_str)
    first = Date.new!(year, month, 1)
    last = Date.new!(year, month, :calendar.last_day_of_the_month(year, month))
    {Date.to_iso8601(first), Date.to_iso8601(last)}
  end

  def period_to_dates("week:" <> start_str) do
    {:ok, start_date} = Date.from_iso8601(start_str)
    end_date = Date.add(start_date, 6)
    {Date.to_iso8601(start_date), Date.to_iso8601(end_date)}
  end
end

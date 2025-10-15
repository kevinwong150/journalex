defmodule Journalex.Trades.ActionChainBuilder do
  @moduledoc """
  Builds action chains for trades by backtracking through related activity statements.

  An action chain traces all activity statements that contributed to a closing trade,
  identifying actions like:
  - open_position: First buy/sell that opens the position
  - add_size: Additional buy/sell in the same direction
  - partial_close: Reducing position size before final close

  ## Strategy
  For a closing trade with quantity Q at time T:
  1. Find the exact activity statement matching time T
  2. Backtrack through prior statements on the same day
  3. Accumulate opposite-direction statements until reaching Q
  4. Include partial closes in the same direction
  5. Validate completeness before returning chain

  ## Error Handling
  Returns `nil` when:
  - Close statement not found (likely wrong datetime)
  - Insufficient prior statements to satisfy quantity
  - Invalid input data (missing ticker, datetime, or quantity)
  """

  @decimal_precision 2
  @seconds_per_day 86_400

  import Ecto.Query, warn: false
  alias Journalex.{Repo, ActivityStatement}

  @doc """
  Build an action chain for a single aggregated trade item.

  ## Parameters
  - `close_trade_item` - Map containing :datetime, :ticker/:symbol, :quantity, :realized_pl
  - `opts` - Options:
    - `:all_statements` - Optional pre-loaded list of activity statements (optimization)

  ## Returns
  A map representing the action chain, or nil if unable to build.

  ## Example
      %{
        "1" => %{
          "activity_statement_id" => 123,
          "action" => "open_position",
          "quantity" => 30,
          "datetime" => ~U[2025-07-10 10:25:00Z]
        },
        "2" => %{
          "activity_statement_id" => 124,
          "action" => "add_size",
          "quantity" => 20,
          "datetime" => ~U[2025-07-10 10:28:00Z]
        }
      }
  """
  def build_action_chain(close_trade_item, opts \\ []) when is_map(close_trade_item) do
    with {:ok, close_dt} <- extract_datetime(close_trade_item),
         {:ok, ticker} <- extract_ticker(close_trade_item),
         {:ok, close_quantity} <- extract_quantity(close_trade_item),
         {:ok, date} <- extract_date(close_dt) do
      # Fetch all activity statements for this ticker on this day, sorted chronologically
      statements =
        case Keyword.get(opts, :all_statements) do
          nil ->
            fetch_statements_for_day(ticker, date, close_dt)

          all when is_list(all) ->
            all
            |> filter_statements(ticker, date, close_dt)
            |> Enum.sort_by(& &1.datetime, DateTime)
        end

      # Build the chain by backtracking from close trade
      build_chain_from_statements(statements, close_quantity, close_dt)
    else
      {:error, _reason} -> nil
    end
  end

  @doc """
  Build action chains for multiple aggregated trade items in batch.

  This is more efficient than calling build_action_chain/2 multiple times
  as it pre-loads all necessary activity statements in one query.

  ## Returns
  A map where keys are trade items (by reference) and values are action chains.
  """
  def build_action_chains_batch(trade_items) when is_list(trade_items) do
    # Extract all unique (ticker, date) combinations
    ticker_dates =
      trade_items
      |> Enum.map(fn item ->
        with {:ok, dt} <- extract_datetime(item),
             {:ok, ticker} <- extract_ticker(item),
             {:ok, date} <- extract_date(dt) do
          {ticker, date}
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # Fetch all activity statements for these ticker-date combinations
    all_statements = fetch_statements_batch(ticker_dates)

    # Build action chain for each trade item
    trade_items
    |> Enum.map(fn item ->
      chain = build_action_chain(item, all_statements: all_statements)
      {item, chain}
    end)
    |> Enum.into(%{})
  end

  # Private functions

  defp extract_datetime(item) do
    dt = Map.get(item, :datetime) || Map.get(item, "datetime")

    cond do
      is_struct(dt, DateTime) -> {:ok, dt}
      is_struct(dt, NaiveDateTime) -> {:ok, DateTime.from_naive!(dt, "Etc/UTC")}
      is_binary(dt) -> parse_datetime_string(dt)
      true -> {:error, :invalid_datetime}
    end
  end

  defp extract_ticker(item) do
    ticker =
      Map.get(item, :ticker) || Map.get(item, :symbol) || Map.get(item, "ticker") ||
        Map.get(item, "symbol")

    if is_binary(ticker) and ticker != "" do
      {:ok, ticker}
    else
      {:error, :invalid_ticker}
    end
  end

  defp extract_quantity(item) do
    qty = Map.get(item, :quantity) || Map.get(item, "quantity")

    cond do
      is_number(qty) ->
        {:ok, Decimal.from_float(qty * 1.0)}

      is_struct(qty, Decimal) ->
        {:ok, qty}

      is_binary(qty) ->
        case Decimal.parse(qty) do
          {decimal, _} -> {:ok, decimal}
          :error -> {:error, :invalid_quantity}
        end

      true ->
        {:error, :invalid_quantity}
    end
  end

  defp extract_date(datetime) do
    {:ok, DateTime.to_date(datetime)}
  end

  defp parse_datetime_string(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      _ ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
          _ -> {:error, :invalid_datetime_string}
        end
    end
  end

  # Fetch activity statements for a specific ticker and date
  defp fetch_statements_for_day(ticker, date, before_dt) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    exclusive_before_dt = before_dt |> truncate_to_second() |> DateTime.add(1, :second)

    from(s in ActivityStatement,
      where: s.symbol == ^ticker,
      where: s.datetime >= ^start_dt,
      where: s.datetime < ^exclusive_before_dt,
      order_by: [asc: s.datetime]
    )
    |> Repo.all()
  end

  # Filter pre-loaded statements for a specific ticker and date
  defp filter_statements(statements, ticker, date, before_dt) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    exclusive_before_dt = before_dt |> truncate_to_second() |> DateTime.add(1, :second)

    statements
    |> Enum.filter(fn s ->
      s.symbol == ticker and
        DateTime.compare(s.datetime, start_dt) in [:gt, :eq] and
        DateTime.compare(s.datetime, exclusive_before_dt) == :lt
    end)
  end

  # Fetch activity statements for multiple ticker-date combinations
  defp fetch_statements_batch(ticker_dates) do
    # Build a query that fetches all needed statements
    queries =
      Enum.map(ticker_dates, fn {ticker, date} ->
        start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

        from(s in ActivityStatement,
          where: s.symbol == ^ticker,
          where: s.datetime >= ^start_dt,
          where: s.datetime <= ^end_dt
        )
      end)

    # Union all queries and execute
    if Enum.empty?(queries) do
      []
    else
      queries
      |> Enum.reduce(fn query, acc -> union(acc, ^query) end)
      |> Repo.all()
    end
  end

  # Build the action chain by backtracking through statements
  defp build_chain_from_statements(statements, close_quantity, close_dt) do
    # Validate input quantity
    if Decimal.eq?(Decimal.abs(close_quantity), Decimal.new(0)) do
      nil
    else
      do_build_chain(statements, close_quantity, close_dt)
    end
  end

  defp do_build_chain(statements, close_quantity, close_dt) do
    # Find the close statement itself first (tolerate sub-second differences)
    truncated_close_dt = truncate_to_second(close_dt)

    close_statement =
      statements
      |> Enum.find(fn stmt ->
        equal_datetimes?(stmt.datetime, truncated_close_dt)
      end)

    close_dt_actual = if(close_statement, do: close_statement.datetime, else: truncated_close_dt)

    # Filter to get only statements BEFORE the close
    statements_before_close =
      statements
      |> Enum.filter(fn stmt ->
        before_datetime?(stmt.datetime, close_dt_actual)
      end)

    # The close_quantity tells us what was closed (e.g., -30 = sold 30)
    # We need to find the opposite operations that opened this position
    # For a sell (-30), we need to find buys (+30 total)
    # For a buy (+40), we need to find sells (-40 total) - for closing a short
    target_quantity = Decimal.abs(close_quantity)
    close_is_sell = Decimal.negative?(close_quantity)

    # Reverse the statements to go backward in time
    reversed_statements = Enum.reverse(statements_before_close)

    # Accumulate statements until we reach the target quantity
    # We're looking for statements in the OPPOSITE direction of the close
    {chain_statements, accumulated_qty} =
      Enum.reduce_while(reversed_statements, {[], Decimal.new(0)}, fn stmt,
                                                                      {acc_stmts, running_qty} ->
        # Only consider statements in the opposite direction of the close
        # If close is a sell (negative), we want buys (positive) and vice versa
        stmt_matches_direction =
          (close_is_sell and Decimal.positive?(stmt.quantity)) or
            (not close_is_sell and Decimal.negative?(stmt.quantity))

        if stmt_matches_direction do
          # Add the absolute value to our running total
          new_qty = Decimal.add(running_qty, Decimal.abs(stmt.quantity))
          new_acc = [stmt | acc_stmts]

          # Check if we've reached or exceeded the target
          cond do
            Decimal.eq?(new_qty, target_quantity) ->
              # Perfect match, we're done
              {:halt, {new_acc, new_qty}}

            Decimal.gt?(new_qty, target_quantity) ->
              # We've exceeded - this shouldn't happen in a clean trade chain
              # but include this statement anyway
              {:halt, {new_acc, new_qty}}

            true ->
              # Keep going
              {:cont, {new_acc, new_qty}}
          end
        else
          # This statement is in the same direction as the close (e.g., another sell)
          # This could be a partial close - include it in the chain
          new_acc = [stmt | acc_stmts]
          {:cont, {new_acc, running_qty}}
        end
      end)

    # Convert to action chain format (chronological order, numbered from 1)
    cond do
      is_nil(close_statement) ->
        # Log: Close statement not found at #{DateTime.to_string(truncated_close_dt)}
        nil

      Enum.empty?(chain_statements) ->
        # Log: No supporting statements found before close
        nil

      Decimal.lt?(accumulated_qty, target_quantity) ->
        # Log: Accumulated #{Decimal.to_string(accumulated_qty)} < target #{Decimal.to_string(target_quantity)}
        nil

      true ->
        build_chain_map(chain_statements, close_statement, close_is_sell)
    end
  end

  # Convert accumulated statements into the final chain map structure
  defp build_chain_map(chain_statements, close_statement, close_is_sell) do
    all_chain_statements = chain_statements ++ [close_statement]

    all_chain_statements
    |> Enum.sort_by(&DateTime.truncate(&1.datetime, :second), DateTime)
    |> Enum.with_index(1)
    |> Enum.map(fn {stmt, idx} ->
      action = determine_action(stmt, idx, length(all_chain_statements), close_is_sell)

      {Integer.to_string(idx),
       %{
         "activity_statement_id" => stmt.id,
         "action" => action,
         "quantity" => Decimal.to_float(stmt.quantity),
         "datetime" => DateTime.to_iso8601(stmt.datetime),
         "price" => (stmt.trade_price && Decimal.to_float(stmt.trade_price))
       }}
    end)
    |> Enum.into(%{})
  end

  # Determine the action type for a statement in the chain
  defp determine_action(stmt, position, total_count, close_is_sell) do
    qty = stmt.quantity

    cond do
      # First opening statement
      position == 1 ->
        "open_position"

      # Last statement is always the close
      position == total_count ->
        "close_position"

      # For statements in between, determine if adding or reducing
      position > 1 and position < total_count ->
        # If this statement is in the opening direction (opposite of close)
        opening_direction = if close_is_sell, do: :positive, else: :negative
        stmt_direction = if Decimal.positive?(qty), do: :positive, else: :negative

        if stmt_direction == opening_direction do
          # Adding to the position
          "add_size"
        else
          # Reducing the position (partial close before final close)
          "partial_close"
        end

      true ->
        "unknown"
    end
  end

  defp truncate_to_second(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp equal_datetimes?(%DateTime{} = lhs, %DateTime{} = rhs) do
    DateTime.compare(truncate_to_second(lhs), truncate_to_second(rhs)) == :eq
  end

  defp before_datetime?(%DateTime{} = lhs, %DateTime{} = rhs) do
    DateTime.compare(lhs, rhs) == :lt
  end
end

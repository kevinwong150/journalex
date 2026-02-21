# Action Chain Builder

## Overview

The Action Chain Builder traces the sequence of activity statements that contributed to a closing trade. This provides a complete audit trail showing how a position was opened, sized, potentially reduced, and finally closed.

## Core Concepts

### Action Types

- **`open_position`**: First statement that initiates the position
- **`add_size`**: Additional entry in the same direction (scaling in)
- **`partial_close`**: Reduction before final close
- **`close_position`**: Final statement that closes the position

### Direction Logic

For a **sell close** (negative quantity):
- We backtrack to find **buy statements** (positive quantity) that opened the position
- Any intermediate sells are classified as partial closes

For a **buy close** (positive quantity, closing a short):
- We backtrack to find **sell statements** (negative quantity) that opened the short
- Any intermediate buys are classified as partial closes

## Usage

### Single Trade

```elixir
close_trade = %{
  datetime: ~U[2025-07-10 14:30:00Z],
  ticker: "AAPL",
  quantity: -50,  # Sold 50 shares
  realized_pl: 250.0
}

action_chain = ActionChainBuilder.build_action_chain(close_trade)
# Returns:
# %{
#   "1" => %{
#     "activity_statement_id" => 123,
#     "action" => "open_position",
#     "quantity" => 30,
#     "datetime" => "2025-07-10T10:25:00Z"
#   },
#   "2" => %{
#     "activity_statement_id" => 124,
#     "action" => "add_size",
#     "quantity" => 20,
#     "datetime" => "2025-07-10T10:28:00Z"
#   },
#   "3" => %{
#     "activity_statement_id" => 125,
#     "action" => "close_position",
#     "quantity" => -50,
#     "datetime" => "2025-07-10T14:30:00Z"
#   }
# }
```

### Batch Processing

```elixir
trades = [trade1, trade2, trade3]
chains = ActionChainBuilder.build_action_chains_batch(trades)
# Returns a map: %{trade1 => chain1, trade2 => chain2, ...}
```

### With Pre-loaded Statements (Performance Optimization)

```elixir
# Fetch all statements for a date range once
statements = Repo.all(
  from s in ActivityStatement,
    where: s.datetime >= ^start_dt and s.datetime <= ^end_dt
)

# Build chains with pre-loaded data
chain = ActionChainBuilder.build_action_chain(
  close_trade,
  all_statements: statements
)
```

## Validation Rules

A chain is only returned when:

1. ✅ Close statement exists at the specified datetime
2. ✅ Close quantity is non-zero
3. ✅ Sufficient prior statements found to satisfy the close quantity
4. ✅ All statements are on the same trading day

Returns `nil` if any validation fails.

## Edge Cases

### Partial Closes

When a position is reduced before final close:

```
10:00 - Buy 100 shares   (open_position)
10:30 - Buy 50 shares    (add_size)
11:00 - Sell 30 shares   (partial_close)
14:00 - Sell 120 shares  (close_position)
```

### Same-Second Trades

The builder tolerates sub-second timestamp differences by truncating to seconds before comparison.

### Insufficient Prior Statements

If a close trade references a position opened on a different day, the chain returns `nil` because we only search the same trading day.

**Solution**: Ensure activity statements for prior days are available, or adjust the date range in queries.

## Performance Considerations

### Query Optimization

- Always use indexed fields: `datetime`, `symbol`
- Batch fetch when processing multiple trades
- Limit query scope to relevant date ranges

### Memory Usage

For large datasets:
- Process trades in chunks
- Use streaming when possible
- Consider async processing for batch operations

## Error Handling

The builder returns `nil` instead of raising errors. Check the return value:

```elixir
case ActionChainBuilder.build_action_chain(trade) do
  nil ->
    Logger.warn("Could not build chain for #{trade.ticker} at #{trade.datetime}")
    # Handle missing chain gracefully
    
  chain ->
    # Proceed with chain data
end
```

## Testing

Example test coverage:

```elixir
test "builds chain for simple long position" do
  # Setup: Insert statements for open and close
  # Assert: Chain contains correct action types and order
end

test "handles partial closes correctly" do
  # Setup: Multiple entries and partial exit
  # Assert: Intermediate statement marked as partial_close
end

test "returns nil for insufficient statements" do
  # Setup: Close without corresponding open
  # Assert: nil returned
end
```

## Migration Guide

If upgrading from manual chain building:

1. Replace custom logic with `ActionChainBuilder.build_action_chain/2`
2. Use `:all_statements` option for pre-loaded data
3. Handle `nil` returns appropriately
4. Test with historical data to ensure compatibility

## Future Enhancements

Potential improvements:

- [ ] Multi-day position tracking
- [ ] Support for fractional shares
- [ ] Configurable quantity tolerance
- [ ] Chain validation API
- [ ] Performance metrics/logging

defmodule Journalex.ActivityStatementParser do
  @moduledoc """
  Parser for Interactive Brokers Activity Statement CSV exports.

  It focuses on extracting Trades (DataDiscriminator == "Order") rows and
  normalizing fields we need to display in the UI table.
  """

  alias NimbleCSV.RFC4180, as: CSV

  @type trade :: %{
          asset_category: String.t(),
          currency: String.t(),
          symbol: String.t(),
          datetime: String.t(),
          quantity: String.t(),
          trade_price: String.t(),
          current_price: String.t() | nil,
          proceeds: String.t() | nil,
          comm_fee: String.t() | nil,
          basis: String.t() | nil,
          realized_pl: String.t() | nil,
          mtm_pl: String.t() | nil,
          code: String.t() | nil
        }

  @doc """
  Parse a CSV file and return a keyword map of sections -> rows.

  You typically want `parse_trades_file/1` for UI display.
  """
  def parse_file(path) when is_binary(path) do
    path
    |> File.read!()
    |> parse_content()
  end

  @doc """
  Parse just the Trades rows that have DataDiscriminator == "Order".
  Returns a list of maps with selected columns.
  """
  @spec parse_trades_file(String.t()) :: [trade()]
  def parse_trades_file(path) do
    path
    |> File.read!()
    |> parse_trades_content()
  end

  @doc false
  def parse_content(csv_content) when is_binary(csv_content) do
    rows = CSV.parse_string(csv_content)

    # We'll just return raw rows grouped by the first column (section name)
    Enum.group_by(rows, fn [section | _] -> section end)
  end

  @doc false
  def parse_trades_content(csv_content) when is_binary(csv_content) do
    rows = CSV.parse_string(csv_content)

    # Identify header positions for Trades table
    # We expect rows like:
    # ["Trades","Header","DataDiscriminator","Asset Category","Currency","Symbol","Date/Time", ...]
    # followed by Data rows starting with ["Trades","Data", ...]

    {headers, data_rows} =
      rows
      |> Enum.reduce({nil, []}, fn row, {hdr, acc} ->
        case row do
          ["Trades", "Header" | header_cols] ->
            {header_cols, acc}

          ["Trades", "Data" | data_cols] when not is_nil(hdr) ->
            {hdr, [data_cols | acc]}

          # Ignore SubTotal/Total rows for UI table of individual orders
          ["Trades", type | _] when type in ["SubTotal", "Total"] ->
            {hdr, acc}

          _ ->
            {hdr, acc}
        end
      end)

    case headers do
      nil ->
        []

      header_cols ->
        # Build index map for column access
        idx =
          header_cols
          |> Enum.with_index()
          |> Map.new()

        data_rows
        |> Enum.reverse()
        |> Enum.filter(fn cols ->
          # DataDiscriminator == "Order"
          case Map.fetch(idx, "DataDiscriminator") do
            {:ok, i} -> Enum.at(cols, i) == "Order"
            :error -> true
          end
        end)
        |> Enum.map(fn cols ->
          %{
            asset_category: pick(cols, idx, "Asset Category"),
            currency: pick(cols, idx, "Currency"),
            symbol: pick(cols, idx, "Symbol"),
            datetime: pick(cols, idx, "Date/Time"),
            quantity: pick(cols, idx, "Quantity"),
            trade_price: pick(cols, idx, "T. Price"),
            current_price: pick(cols, idx, "C. Price"),
            proceeds: pick(cols, idx, "Proceeds"),
            comm_fee: pick(cols, idx, "Comm/Fee"),
            basis: pick(cols, idx, "Basis"),
            realized_pl: pick(cols, idx, "Realized P/L"),
            mtm_pl: pick(cols, idx, "MTM P/L"),
            code: pick(cols, idx, "Code")
          }
        end)
    end
  end

  defp pick(cols, idx, key) do
    case Map.fetch(idx, key) do
      {:ok, i} -> Enum.at(cols, i)
      :error -> nil
    end
  end

  @doc """
  Parse the statement period (date) from a CSV file.

  Returns a string like "September 23, 2025" or nil if not found.
  """
  @spec parse_period_file(String.t()) :: String.t() | nil
  def parse_period_file(path) do
    path
    |> File.read!()
    |> parse_period_content()
  end

  @doc false
  def parse_period_content(csv_content) do
    csv_content
    |> CSV.parse_string()
    |> Enum.find_value(fn
      ["Statement", "Data", "Period", value | _rest] -> value
      _ -> nil
    end)
  end
end

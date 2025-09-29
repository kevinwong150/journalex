defmodule Journalex.Notion do
  @moduledoc """
  High-level helpers to interact with Notion for Journalex workflows.
  """

  alias Journalex.Notion.Client

  @doc """
  Checks whether a page exists in the data source matching the given timestamp.

  Uses configuration from `:journalex, Journalex.Notion` for defaults:
  * :data_source_id
  * :datetime_property (default "Datetime")

  Returns `{:ok, true | false}` or `{:error, reason}`.
  """
  def exists_by_timestamp?(%DateTime{} = dt, opts \\ []) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = Keyword.get(opts, :data_source_id, conf[:data_source_id])
    property = Keyword.get(opts, :datetime_property, conf[:datetime_property] || "Datetime")

    if is_nil(data_source_id) do
      {:error, :missing_data_source_id}
    else
      iso = DateTime.to_iso8601(dt)

      body = %{
        filter: %{
          property: property,
          date: %{equals: iso}
        },
        page_size: 1
      }

      case Client.query_database(data_source_id, body) do
        {:ok, %{"results" => results}} when is_list(results) -> {:ok, length(results) > 0}
        {:ok, other} -> {:error, {:unexpected_response, other}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Checks whether a page exists matching both timestamp and ticker text property.

  Options:
    * :data_source_id - overrides configured data source id
    * :datetime_property - overrides the date property name
    * :ticker_property - overrides the rich_text property for ticker/symbol (default "Ticker")
  """
  def exists_by_timestamp_and_ticker?(%DateTime{} = dt, ticker, opts \\ [])
      when is_binary(ticker) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = Keyword.get(opts, :data_source_id, conf[:data_source_id])
    ts_prop = Keyword.get(opts, :datetime_property, conf[:datetime_property] || "Datetime")
    tk_prop = Keyword.get(opts, :ticker_property, conf[:ticker_property] || "Ticker")

    if is_nil(data_source_id) do
      {:error, :missing_data_source_id}
    else
      iso = DateTime.to_iso8601(dt)

      body = %{
        filter: %{
          "and" => [
            %{property: ts_prop, date: %{equals: iso}},
            %{property: tk_prop, rich_text: %{equals: ticker}}
          ]
        },
        page_size: 1
      }

      case Client.query_database(data_source_id, body) do
        {:ok, %{"results" => results}} when is_list(results) -> {:ok, length(results) > 0}
        {:ok, other} -> {:error, {:unexpected_response, other}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Creates a Notion page for a given statement row.

  Required configured keys in `:journalex, Journalex.Notion`:
    * :data_source_id - the Notion data source id (new API)
    * :datetime_property (default "Datetime")
    * :ticker_property (default "Ticker")
    * :title_property (default "Trademark")

  Creates a minimal page with Title, Datetime (date), and Ticker (rich_text).
  """
  def create_from_statement(row, opts \\ []) when is_map(row) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = Keyword.get(opts, :data_source_id, conf[:data_source_id])
    ts_prop = Keyword.get(opts, :datetime_property, conf[:datetime_property] || "Datetime")
    tk_prop = Keyword.get(opts, :ticker_property, conf[:ticker_property] || "Ticker")
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")

    dt = Map.get(row, :datetime) || Map.get(row, "datetime")
    ticker = Map.get(row, :symbol) || Map.get(row, "symbol")

    cond do
      is_nil(data_source_id) ->
        {:error, :missing_data_source_id}

      is_nil(dt) or is_nil(ticker) ->
        {:error, :missing_required_fields}

      true ->
        iso = DateTime.to_iso8601(dt)
        title = ticker <> "@" <> iso

        # Optional fields (if present in the row) mapped to sensible Notion types
        side = Map.get(row, :side) || Map.get(row, "side")
        position_action = Map.get(row, :position_action) || Map.get(row, "position_action")
        currency = Map.get(row, :currency) || Map.get(row, "currency")
        qty = to_number(Map.get(row, :quantity) || Map.get(row, "quantity"))
        realized = to_number(Map.get(row, :realized_pl) || Map.get(row, "realized_pl"))
        trade_price = to_number(Map.get(row, :trade_price) || Map.get(row, "trade_price"))

        base_props = %{
          title_prop => %{title: [%{text: %{content: title}}]},
          ts_prop => %{date: %{start: iso}},
          tk_prop => %{rich_text: %{text: ticker}}
        }

        extra_props =
          %{}
          |> maybe_put_select("Side", side)
          |> maybe_put_select("Position Action", position_action)
          |> maybe_put_select("Currency", currency)
          |> maybe_put_number("Quantity", qty)
          |> maybe_put_number("Realized P/L", realized)
          |> maybe_put_number("Trade Price", trade_price)

        payload = %{
          "parent" => %{"database_id" => data_source_id},
          "properties" => Map.merge(base_props, extra_props)
        }

        case Client.create_page(payload) do
          {:ok, map} -> {:ok, map}
          {:error, reason} -> {:error, reason}
          other -> other
        end
    end
  end

  # Helpers to build optional Notion properties safely
  defp maybe_put_select(map, _key, nil), do: map

  defp maybe_put_select(map, key, value) when is_binary(value) and value != "" do
    Map.put(map, key, %{select: %{name: value}})
  end

  defp maybe_put_select(map, _key, _), do: map

  defp maybe_put_number(map, _key, nil), do: map

  defp maybe_put_number(map, key, value) when is_number(value) do
    Map.put(map, key, %{number: value})
  end

  defp maybe_put_number(map, _key, _), do: map

  defp to_number(nil), do: nil
  defp to_number(""), do: nil
  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(n) when is_number(n), do: n * 1.0

  defp to_number(s) when is_binary(s) do
    s
    |> String.trim()
    |> String.replace(",", "")
    |> case do
      "" ->
        nil

      str ->
        case Float.parse(str) do
          {n, _} -> n
          :error -> nil
        end
    end
  end
end

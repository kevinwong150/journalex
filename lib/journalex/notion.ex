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
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")

    if is_nil(data_source_id) do
      {:error, :missing_data_source_id}
    else
      iso = DateTime.to_iso8601(dt)
      title = ticker <> "@" <> iso

      body = %{
        filter: %{
          "and" => [
            %{property: title_prop, rich_text: %{equals: title}},
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
        side = (Map.get(row, :side) || Map.get(row, "side")) |> capitalize_words()

        position_action =
          (Map.get(row, :position_action) || Map.get(row, "position_action"))
          |> capitalize_words()

        currency = Map.get(row, :currency) || Map.get(row, "currency")
        qty = to_number(Map.get(row, :quantity) || Map.get(row, "quantity"))
        realized = to_number(Map.get(row, :realized_pl) || Map.get(row, "realized_pl"))
        trade_price = to_number(Map.get(row, :trade_price) || Map.get(row, "trade_price"))

        base_props = %{
          title_prop => %{title: [%{text: %{content: title}}]},
          ts_prop => %{date: %{start: iso}},
          tk_prop => %{rich_text: [%{text: %{content: ticker}}]}
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
          "parent" => %{"data_source_id" => data_source_id},
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

  # Capitalize each word (title-case) in a string; returns nil unchanged
  defp capitalize_words(nil), do: nil

  defp capitalize_words(s) when is_binary(s) do
    s
    |> String.trim()
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp capitalize_words(other), do: other

  @doc """
  List all pages in the configured Notion data source and return a Set of
  "Trademark" property values (or the configured title property).

  Options:
    * :data_source_id - overrides configured data source id
    * :title_property - overrides the title property name (default "Trademark")
    * :page_size - query page size for pagination (default 100)

  Returns `{:ok, MapSet.t()}` or `{:error, reason}`.
  """
  def list_all_trademarks(opts \\ []) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = Keyword.get(opts, :data_source_id, conf[:data_source_id])
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")
    page_size = Keyword.get(opts, :page_size, 10000)

    if is_nil(data_source_id) do
      {:error, :missing_data_source_id}
    else
      # Prefer retrieving the whole database in one request
      case Client.retrieve_database(data_source_id) do
        {:ok, resp} ->
          case extract_pages_from_db_response(resp) do
            {:ok, pages} ->
              titles =
                pages
                |> Enum.map(&extract_title(&1, title_prop))
                |> Enum.reject(&is_nil/1)
                |> MapSet.new()

              {:ok, titles}

            {:error, _} ->
              # Fallback to paginated queries if the response didn't include records
              with {:ok, pages} <- paginate_all_pages(data_source_id, page_size) do
                titles =
                  pages
                  |> Enum.map(&extract_title(&1, title_prop))
                  |> Enum.reject(&is_nil/1)
                  |> MapSet.new()

                {:ok, titles}
              end
          end

        {:error, _reason} ->
          # Fallback to paginated queries on error
          with {:ok, pages} <- paginate_all_pages(data_source_id, page_size) do
            titles =
              pages
              |> Enum.map(&extract_title(&1, title_prop))
              |> Enum.reject(&is_nil/1)
              |> MapSet.new()

            {:ok, titles}
          end
      end
    end
  end

  # --- Internal helpers for pagination and parsing ---

  defp paginate_all_pages(data_source_id, page_size) do
    do_page(data_source_id, page_size, nil, [])
  end

  defp do_page(data_source_id, page_size, start_cursor, acc) do
    body =
      %{
        page_size: page_size
      }
      |> maybe_put_start_cursor(start_cursor)

    case Client.query_database(data_source_id, body) do
      {:ok, %{"results" => results} = resp} when is_list(results) ->
        acc = acc ++ results

        case resp do
          %{"has_more" => true, "next_cursor" => cursor} when is_binary(cursor) ->
            do_page(data_source_id, page_size, cursor, acc)

          _ ->
            {:ok, acc}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_start_cursor(map, nil), do: map

  defp maybe_put_start_cursor(map, cursor) when is_binary(cursor),
    do: Map.put(map, :start_cursor, cursor)

  defp extract_title(page, title_prop) do
    case get_in(page, ["properties", title_prop, "title"]) do
      list when is_list(list) and list != [] ->
        first = hd(list)
        # Prefer plain_text if present, fallback to nested text.content
        Map.get(first, "plain_text") || get_in(first, ["text", "content"]) ||
          get_in(first, ["annotations", "plain_text"]) || nil

      _ ->
        nil
    end
  end

  # Try to extract a list of page objects from different possible response shapes
  defp extract_pages_from_db_response(%{"results" => results}) when is_list(results),
    do: {:ok, results}

  defp extract_pages_from_db_response(%{"pages" => pages}) when is_list(pages), do: {:ok, pages}

  defp extract_pages_from_db_response(%{"items" => items}) when is_list(items), do: {:ok, items}

  defp extract_pages_from_db_response(%{"data" => %{"results" => results}}) when is_list(results),
    do: {:ok, results}

  defp extract_pages_from_db_response(_), do: {:error, :no_pages_in_response}
end

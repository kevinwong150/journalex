defmodule Journalex.Notion do
  @moduledoc """
  High-level helpers to interact with Notion for Journalex workflows.
  """

  alias Journalex.Notion.Client

  @doc """
  Checks whether a page exists in the data source matching the given timestamp.

  Uses configuration from `:journalex, Journalex.Notion` for defaults:
  * :activity_statements_data_source_id
  * :datetime_property (default "Datetime")

  Returns `{:ok, true | false}` or `{:error, reason}`.
  """
  def exists_by_timestamp?(%DateTime{} = dt, opts \\ []) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    # Allow choosing which Notion database to use; default to activity statements
    data_source_id = resolve_data_source_id(opts, conf, :activity)
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
    # Allow choosing which Notion database to use; default to activity statements
    data_source_id = resolve_data_source_id(opts, conf, :activity)
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
    * :activity_statements_data_source_id - the Notion data source id for activity statements
    * :datetime_property (default "Datetime")
    * :ticker_property (default "Ticker")
    * :title_property (default "Trademark")

  Creates a minimal page with Title, Datetime (date), and Ticker (rich_text).
  """
  def create_from_statement(row, opts \\ []) when is_map(row) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    # Force using the activity statements database unless explicitly overridden
    data_source_id = resolve_data_source_id(opts, conf, :activity)
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
        end
    end
  end

  @doc """
  Creates a Notion page for a given aggregated trade row.

  Required configured keys in `:journalex, Journalex.Notion`:
    * :trades_data_source_id - the Notion data source id for trades (preferred)
      Falls back to :activity_statements_data_source_id if not set.
    * :datetime_property (default "Datetime")
    * :ticker_property (default "Ticker")
    * :title_property (default "Trademark")

  Expects a map with keys:
    - :datetime (DateTime)
    - :ticker (string) or :symbol
    - optional: :aggregated_side ("LONG"|"SHORT"|"-")
    - optional: :result ("WIN"|"LOSE")
    - optional: :realized_pl (number|Decimal|string)
  """
  def create_from_trade(row, opts \\ []) when is_map(row) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    # Prefer the trades database for trades, with sensible fallbacks
    data_source_id = resolve_data_source_id(opts, conf, :trades)

    ts_prop = Keyword.get(opts, :datetime_property, conf[:datetime_property] || "Datetime")
    tk_prop = Keyword.get(opts, :ticker_property, conf[:ticker_property] || "Ticker")
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")

    dt = Map.get(row, :datetime) || Map.get(row, "datetime")

    ticker =
      Map.get(row, :ticker) || Map.get(row, :symbol) || Map.get(row, "ticker") ||
        Map.get(row, "symbol")

    cond do
      is_nil(data_source_id) ->
        {:error, :missing_data_source_id}

      is_nil(dt) or is_nil(ticker) ->
        {:error, :missing_required_fields}

      true ->
        iso = DateTime.to_iso8601(dt)
        title = ticker <> "@" <> iso

        agg_side = Map.get(row, :aggregated_side) || Map.get(row, "aggregated_side")
        result = Map.get(row, :result) || Map.get(row, "result")
        realized = to_number(Map.get(row, :realized_pl) || Map.get(row, "realized_pl"))
        duration_secs = row_duration_seconds(row)
        entry_slot_label = entry_timeslot_bucket(row)

        base_props = %{
          title_prop => %{title: [%{text: %{content: title}}]},
          ts_prop => %{date: %{start: iso}},
          tk_prop => %{rich_text: [%{text: %{content: to_string(ticker)}}]}
        }

        # Entry/Close Timeslot property names differ between V1 and V2
        version = Map.get(row, :metadata_version) || 2
        entry_timeslot_prop = if version == 1, do: "Entry Timeslot", else: "EntryTimeslot"
        close_slot_label = close_timeslot_bucket(row)

        extra_props =
          %{}
          |> maybe_put_select("Side", agg_side)
          |> maybe_put_select("Result", result)
          |> maybe_put_number("Realized P/L", realized)
          |> maybe_put_number("Duration", duration_secs)
          |> maybe_put_select(entry_timeslot_prop, entry_slot_label)
          |> then(fn props ->
            if version == 2, do: maybe_put_select(props, "CloseTimeslot", close_slot_label), else: props
          end)

        # Add relation links (TickerLink, DateLink) if page IDs provided via opts
        ticker_page_id = Keyword.get(opts, :ticker_page_id)
        date_page_id = Keyword.get(opts, :date_page_id)

        relation_props =
          %{}
          |> maybe_put_relation("TickerLink", ticker_page_id)
          |> maybe_put_relation("DateLink", date_page_id)

        # Add metadata fields if present
        metadata_props = build_metadata_properties(row)

        payload = %{
          "parent" => %{"data_source_id" => data_source_id},
          "properties" =>
            base_props
            |> Map.merge(extra_props)
            |> Map.merge(relation_props)
            |> Map.merge(metadata_props)
        }

        case Client.create_page(payload) do
          {:ok, map} -> {:ok, map}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Compare a trade row with a Notion page map and return a map of mismatched fields.

  Compares base trade fields (Title, Ticker, Side, Result, Realized P/L, Duration,
  Entry Timeslot) plus all metadata form fields for the trade's version (V1 or V2).

  Entry/Close Timeslot property names are version-aware:
  - V1: "Entry Timeslot" (with space)
  - V2: "EntryTimeslot" / "CloseTimeslot" (CamelCase)

  Returns a map like `%{field => %{expected: v1, actual: v2}}` or `%{}` if no diffs.
  """
  def diff_trade_vs_page(row, page, opts \\ []) when is_map(row) and is_map(page) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    ts_prop = Keyword.get(opts, :datetime_property, conf[:datetime_property] || "Datetime")
    tk_prop = Keyword.get(opts, :ticker_property, conf[:ticker_property] || "Ticker")
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")

    dt = Map.get(row, :datetime) || Map.get(row, "datetime")

    ticker =
      Map.get(row, :ticker) || Map.get(row, :symbol) || Map.get(row, "ticker") ||
        Map.get(row, "symbol")

    agg_side = Map.get(row, :aggregated_side) || Map.get(row, "aggregated_side")
    result = Map.get(row, :result) || Map.get(row, "result")
    realized = to_number(Map.get(row, :realized_pl) || Map.get(row, "realized_pl"))
    duration_secs = row_duration_seconds(row)
    entry_slot_label = entry_timeslot_bucket(row)
    version = Map.get(row, :metadata_version) || 2

    # Version-aware property names
    entry_timeslot_prop = if version == 1, do: "Entry Timeslot", else: "EntryTimeslot"

    iso = if dt, do: DateTime.to_iso8601(dt), else: nil
    title = if ticker && iso, do: ticker <> "@" <> iso, else: nil

    actual_title = page |> get_in(["properties", title_prop, "title"]) |> first_rich_text()
    _actual_date = page |> get_in(["properties", ts_prop, "date", "start"]) || nil
    actual_ticker = page |> get_in(["properties", tk_prop, "rich_text"]) |> first_rich_text()
    actual_side = page |> get_in(["properties", "Side", "select", "name"]) || nil
    actual_result = page |> get_in(["properties", "Result", "select", "name"]) || nil
    actual_realized = page |> get_in(["properties", "Realized P/L", "number"]) || nil
    actual_duration = page |> get_in(["properties", "Duration", "number"]) || nil
    actual_entry_slot = page |> get_in(["properties", entry_timeslot_prop, "select", "name"]) || nil

    # Base trade field comparison
    base_diffs =
      %{}
      |> maybe_put_diff(:title, title, actual_title)
      # Skip datetime mismatches per requirement
      # |> maybe_put_diff(:datetime, iso, actual_date)
      |> maybe_put_diff(:ticker, to_string(ticker || ""), actual_ticker)
      |> maybe_put_diff(:side, normalize_string(agg_side), normalize_string(actual_side))
      |> maybe_put_diff(:result, normalize_string(result), normalize_string(actual_result))
      |> maybe_put_diff(:realized_pl, realized, to_number(actual_realized))
      |> maybe_put_diff(:duration, to_number(duration_secs), to_number(actual_duration))
      |> maybe_put_diff(:entry_timeslot, entry_slot_label, normalize_string(actual_entry_slot))

    # Add close_timeslot comparison for V2 (computed from action_chain)
    base_diffs =
      if version == 2 do
        close_slot_label = close_timeslot_bucket(row)
        actual_close_slot = page |> get_in(["properties", "CloseTimeslot", "select", "name"]) || nil
        maybe_put_diff(base_diffs, :close_timeslot, close_slot_label, normalize_string(actual_close_slot))
      else
        base_diffs
      end

    # Metadata field comparison — compare DB metadata against Notion page properties
    properties = Map.get(page, "properties", %{})
    notion_meta = extract_metadata_from_properties(properties, version)
    db_meta = Map.get(row, :metadata) || %{}

    metadata_diff_fields(version)
    |> Enum.reduce(base_diffs, fn {field, type}, acc ->
      db_val = get_meta_field(db_meta, field)
      notion_val = Map.get(notion_meta, field)

      case type do
        :boolean ->
          # Normalize nil to false for checkbox comparison (Notion checkboxes always have a value)
          maybe_put_diff(acc, field, db_val == true, notion_val == true)

        :select ->
          maybe_put_diff(acc, field, normalize_string(db_val), normalize_string(notion_val))

        :number ->
          maybe_put_diff(acc, field, to_number(db_val), to_number(notion_val))

        :multi_select ->
          maybe_put_diff(acc, field, normalize_multi_select(db_val), normalize_multi_select(notion_val))
      end
    end)
  end

  @spec update_trade_page(binary(), map()) ::
          {:error,
           :missing_notion_api_token
           | {:http_error, non_neg_integer(), map()}
           | %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, map()}
  @doc """
  Update a Notion page to match the given trade row. Returns {:ok, map} or {:error, reason}.
  Only sends properties present in the trade row; does not attempt to change parent.
  """
  def update_trade_page(page_id, row, opts \\ []) when is_binary(page_id) and is_map(row) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    ts_prop = Keyword.get(opts, :datetime_property, conf[:datetime_property] || "Datetime")
    tk_prop = Keyword.get(opts, :ticker_property, conf[:ticker_property] || "Ticker")
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")

    dt = Map.get(row, :datetime) || Map.get(row, "datetime")

    ticker =
      Map.get(row, :ticker) || Map.get(row, :symbol) || Map.get(row, "ticker") ||
        Map.get(row, "symbol")

    iso = if dt, do: DateTime.to_iso8601(dt), else: nil
    title = if ticker && iso, do: to_string(ticker) <> "@" <> iso, else: nil

    agg_side = Map.get(row, :aggregated_side) || Map.get(row, "aggregated_side")
    result = Map.get(row, :result) || Map.get(row, "result")
    realized = to_number(Map.get(row, :realized_pl) || Map.get(row, "realized_pl"))
    duration_secs = row_duration_seconds(row)
    entry_slot_label = entry_timeslot_bucket(row)

    base_props = %{}

    base_props =
      if title,
        do: Map.put(base_props, title_prop, %{title: [%{text: %{content: title}}]}),
        else: base_props

    base_props =
      if iso, do: Map.put(base_props, ts_prop, %{date: %{start: iso}}), else: base_props

    base_props =
      if ticker,
        do: Map.put(base_props, tk_prop, %{rich_text: [%{text: %{content: to_string(ticker)}}]}),
        else: base_props

    # Entry/Close Timeslot property names differ between V1 and V2
    version = Map.get(row, :metadata_version) || 2
    entry_timeslot_prop = if version == 1, do: "Entry Timeslot", else: "EntryTimeslot"
    close_slot_label = close_timeslot_bucket(row)

    extra_props = %{}
    extra_props = maybe_put_select(extra_props, "Side", normalize_string(agg_side))
    extra_props = maybe_put_select(extra_props, "Result", normalize_string(result))
    extra_props = maybe_put_number(extra_props, "Realized P/L", realized)
    extra_props = maybe_put_number(extra_props, "Duration", duration_secs)
    extra_props = maybe_put_select(extra_props, entry_timeslot_prop, entry_slot_label)
    extra_props = if version == 2, do: maybe_put_select(extra_props, "CloseTimeslot", close_slot_label), else: extra_props

    # Add metadata fields if present
    metadata_props = build_metadata_properties(row)

    payload = %{"properties" => base_props |> Map.merge(extra_props) |> Map.merge(metadata_props)}

    Client.update_page(page_id, payload)
  end

  @doc """
  Sync metadata from a Notion page back to a trade record.

  Fetches the Notion page, extracts metadata properties, detects the version,
  and updates the trade's metadata and metadata_version fields.

  Returns {:ok, updated_trade} on success or {:error, reason} on failure.

  ## Examples

      iex> Notion.sync_metadata_from_notion(trade.id, "notion-page-id-123")
      {:ok, %Trade{metadata: %TradeMetadata{done?: true, ...}, metadata_version: 2}}
  """
  def sync_metadata_from_notion(trade_id, page_id) when is_binary(page_id) do
    alias Journalex.Repo
    alias Journalex.Trades.Trade
    alias Journalex.Notion.DataSources

    with {:ok, trade} <- Repo.get(Trade, trade_id) |> validate_trade(),
         {:ok, page} <- Client.retrieve_page(page_id),
         properties <- Map.get(page |> IO.inspect(label: :page, limit: :infinity), "properties", %{}),
         parent <- Map.get(page, "parent", %{}),
         data_source_id <- Map.get(parent, "data_source_id"),
         version <- DataSources.get_version(data_source_id) || 2,
         metadata_attrs <- extract_metadata_from_properties(properties, version) do
      # Convert atom keys from extractor to strings to match the JSONB string-keyed format from DB,
      # then merge to preserve existing fields like notion_page_id
      metadata_attrs_str = Map.new(metadata_attrs |> IO.inspect(label: :metadata_attrs, limit: :infinity), fn {k, v} -> {Atom.to_string(k), v} end)
      merged_meta = Map.merge(trade.metadata || %{}, metadata_attrs_str)

      trade
      |> Trade.changeset(%{metadata: merged_meta, metadata_version: version})
      |> Repo.update()
    end
  end

  defp validate_trade(nil), do: {:error, :trade_not_found}
  defp validate_trade(trade), do: {:ok, trade}

  # Route metadata extraction by version
  defp extract_metadata_from_properties(properties, 1),
    do: extract_v1_metadata_from_properties(properties)

  defp extract_metadata_from_properties(properties, _),
    do: extract_v2_metadata_from_properties(properties)

  # Extract V1 metadata attributes from Notion page properties (original Notion structure).
  # Property names use CamelCase (no spaces) as found in the actual V1 Notion database.
  defp extract_v1_metadata_from_properties(properties) when is_map(properties) do
    %{}
    # Status & control
    |> put_if_present(:done?, get_checkbox(properties, "Done?"))
    |> put_if_present(:lost_data?, get_checkbox(properties, "LostData?"))
    # Trade classification
    |> put_if_present(:rank, get_select(properties, "Rank"))
    |> put_if_present(:setup, get_select(properties, "Setup"))
    |> put_if_present(:close_trigger, get_select(properties, "CloseTrigger"))
    |> put_if_present(:sector, get_rollup_first_select(properties, "Sector"))
    |> put_if_present(:cap_size, get_rollup_first_select(properties, "CapSize"))
    |> put_if_present(:entry_timeslot, get_select(properties, "Entry Timeslot"))
    # Boolean flags (V1-specific)
    |> put_if_present(:operation_mistake?, get_checkbox(properties, "OperationMistake?"))
    |> put_if_present(:follow_setup?, get_checkbox(properties, "FollowSetup?"))
    |> put_if_present(:follow_stop_loss_management?, get_checkbox(properties, "FollowStopLossManagement?"))
    |> put_if_present(:revenge_trade?, get_checkbox(properties, "RevengeTrade?"))
    |> put_if_present(:fomo?, get_checkbox(properties, "FOMO?"))
    |> put_if_present(:unnecessary_trade?, get_checkbox(properties, "UnnecessaryTrade?"))
    # Comments (multi_select joined as comma-separated text)
    |> put_if_present(:close_time_comment, get_multi_select_text(properties, "CloseTimeComment"))
  end

  defp extract_v1_metadata_from_properties(_), do: %{}

  # Extract V2 metadata attributes from Notion page properties (enhanced Notion structure).
  # Property names use CamelCase (no spaces) as found in the actual V2 Notion database.
  defp extract_v2_metadata_from_properties(properties) when is_map(properties) do
    %{}
    # Status & control
    |> put_if_present(:done?, get_checkbox(properties, "Done?"))
    |> put_if_present(:lost_data?, get_checkbox(properties, "LostData?"))
    # Trade classification
    |> put_if_present(:rank, get_select(properties, "Rank"))
    |> put_if_present(:setup, get_select(properties, "Setup"))
    |> put_if_present(:close_trigger, get_select(properties, "CloseTrigger"))
    |> put_if_present(:sector, get_rollup_first_select(properties, "Sector"))
    |> put_if_present(:cap_size, get_rollup_first_select(properties, "CapSize"))
    # Risk/reward metrics
    |> put_if_present(:initial_risk_reward_ratio, get_number(properties, "InitialRiskRewardRatio"))
    |> put_if_present(:best_risk_reward_ratio, get_number(properties, "BestRiskRewardRatio"))
    # Position sizing
    |> put_if_present(:size, get_number(properties, "Size"))
    |> put_if_present(:order_type, get_select(properties, "OrderType"))
    # Time
    |> put_if_present(:entry_timeslot, get_select(properties, "EntryTimeslot"))
    |> put_if_present(:close_timeslot, get_select(properties, "CloseTimeslot"))
    # Boolean flags
    |> put_if_present(:revenge_trade?, get_checkbox(properties, "RevengeTrade?"))
    |> put_if_present(:fomo?, get_checkbox(properties, "FOMO?"))
    |> put_if_present(:add_size?, get_checkbox(properties, "AddSize?"))
    |> put_if_present(:adjusted_risk_reward?, get_checkbox(properties, "AdjustedRiskReward?"))
    |> put_if_present(:align_with_trend?, get_checkbox(properties, "AlignWithTrend?"))
    |> put_if_present(:better_risk_reward_ratio?, get_checkbox(properties, "BetterRiskRewardRatio?"))
    |> put_if_present(:big_picture?, get_checkbox(properties, "BigPicture?"))
    |> put_if_present(:earning_report?, get_checkbox(properties, "EarningReport?"))
    |> put_if_present(:follow_up_trial?, get_checkbox(properties, "FollowUpTrial?"))
    |> put_if_present(:good_lesson?, get_checkbox(properties, "GoodLesson?"))
    |> put_if_present(:hot_sector?, get_checkbox(properties, "HotSector?"))
    |> put_if_present(:momentum?, get_checkbox(properties, "Momentum?"))
    |> put_if_present(:news?, get_checkbox(properties, "News?"))
    |> put_if_present(:normal_emotion?, get_checkbox(properties, "NormalEmotion?"))
    |> put_if_present(:operation_mistake?, get_checkbox(properties, "OperationMistake?"))
    |> put_if_present(:overnight?, get_checkbox(properties, "Overnight?"))
    |> put_if_present(:overnight_in_purpose?, get_checkbox(properties, "OvernightInPurpose?"))
    |> put_if_present(:slipped_position?, get_checkbox(properties, "SlippedPosition?"))
    # Comments (multi_select joined as comma-separated text)
    |> put_if_present(:close_time_comment, get_multi_select_text(properties, "CloseTimeComment"))
  end

  defp extract_v2_metadata_from_properties(_), do: %{}

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp get_checkbox(properties, key) do
    case Map.get(properties, key) do
      %{"checkbox" => value} when is_boolean(value) -> value
      _ -> nil
    end
  end

  defp get_select(properties, key) do
    case Map.get(properties, key) do
      %{"select" => %{"name" => name}} when is_binary(name) -> name
      _ -> nil
    end
  end

  defp get_number(properties, key) do
    case Map.get(properties, key) do
      %{"number" => value} when is_number(value) -> Decimal.new(to_string(value))
      _ -> nil
    end
  end

  defp get_rich_text(properties, key) do
    case Map.get(properties, key) do
      %{"rich_text" => list} when is_list(list) -> first_rich_text(list)
      _ -> nil
    end
  end

  # --- local compare helpers ---
  defp first_rich_text(list) when is_list(list) and list != [] do
    first = hd(list)
    Map.get(first, "plain_text") || get_in(first, ["text", "content"]) || nil
  end

  defp first_rich_text(_), do: nil

  defp maybe_put_diff(map, _key, nil, nil), do: map

  defp maybe_put_diff(map, key, expected, actual) do
    if expected == actual do
      map
    else
      Map.put(map, key, %{expected: expected, actual: actual})
    end
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(s) when is_binary(s) do
    s
    |> String.trim()
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp normalize_string(other), do: other

  # Metadata fields to compare per version in diff_trade_vs_page.
  # Excludes: entry_timeslot/close_timeslot (in base comparison),
  # sector/cap_size (rollups, read-only), notion_page_id (internal), trademark (title in base).
  defp metadata_diff_fields(1) do
    [
      {:done?, :boolean},
      {:lost_data?, :boolean},
      {:rank, :select},
      {:setup, :select},
      {:close_trigger, :select},
      {:operation_mistake?, :boolean},
      {:follow_setup?, :boolean},
      {:follow_stop_loss_management?, :boolean},
      {:revenge_trade?, :boolean},
      {:fomo?, :boolean},
      {:unnecessary_trade?, :boolean},
      {:close_time_comment, :multi_select}
    ]
  end

  defp metadata_diff_fields(_version) do
    [
      {:done?, :boolean},
      {:lost_data?, :boolean},
      {:rank, :select},
      {:setup, :select},
      {:close_trigger, :select},
      {:initial_risk_reward_ratio, :number},
      {:best_risk_reward_ratio, :number},
      {:size, :number},
      {:order_type, :select},
      {:revenge_trade?, :boolean},
      {:fomo?, :boolean},
      {:add_size?, :boolean},
      {:adjusted_risk_reward?, :boolean},
      {:align_with_trend?, :boolean},
      {:better_risk_reward_ratio?, :boolean},
      {:big_picture?, :boolean},
      {:earning_report?, :boolean},
      {:follow_up_trial?, :boolean},
      {:good_lesson?, :boolean},
      {:hot_sector?, :boolean},
      {:momentum?, :boolean},
      {:news?, :boolean},
      {:normal_emotion?, :boolean},
      {:operation_mistake?, :boolean},
      {:overnight?, :boolean},
      {:overnight_in_purpose?, :boolean},
      {:slipped_position?, :boolean},
      {:close_time_comment, :multi_select}
    ]
  end

  # Normalize multi_select strings for order-independent comparison
  defp normalize_multi_select(nil), do: nil
  defp normalize_multi_select(""), do: nil

  defp normalize_multi_select(s) when is_binary(s) do
    s
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.sort()
    |> Enum.join(", ")
  end

  defp normalize_multi_select(_), do: nil

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

  defp maybe_put_checkbox(map, _key, nil), do: map

  defp maybe_put_checkbox(map, key, value) when is_boolean(value) do
    Map.put(map, key, %{checkbox: value})
  end

  defp maybe_put_checkbox(map, _key, _), do: map

  defp maybe_put_rich_text(map, _key, nil), do: map
  defp maybe_put_rich_text(map, _key, ""), do: map

  defp maybe_put_rich_text(map, key, value) when is_binary(value) do
    Map.put(map, key, %{rich_text: [%{text: %{content: value}}]})
  end

  defp maybe_put_rich_text(map, _key, _), do: map

  defp maybe_put_relation(map, _key, nil), do: map
  defp maybe_put_relation(map, _key, ""), do: map

  defp maybe_put_relation(map, key, page_id) when is_binary(page_id) do
    Map.put(map, key, %{relation: [%{id: page_id}]})
  end

  defp maybe_put_relation(map, _key, _), do: map

  # Extract the first select name from a rollup array property (read-only in Notion).
  # Shape: %{"rollup" => %{"array" => [%{"select" => %{"name" => "Value"}}]}}
  defp get_rollup_first_select(properties, key) do
    case Map.get(properties, key) do
      %{"rollup" => %{"array" => [%{"select" => %{"name" => name}} | _]}} when is_binary(name) ->
        name

      _ ->
        nil
    end
  end

  # Join all multi_select option names into a comma-separated string.
  # Shape: %{"multi_select" => [%{"name" => "A"}, %{"name" => "B"}]}
  defp get_multi_select_text(properties, key) do
    case Map.get(properties, key) do
      %{"multi_select" => options} when is_list(options) and options != [] ->
        options
        |> Enum.map(&Map.get(&1, "name"))
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")

      _ ->
        nil
    end
  end

  # Build a multi_select property from a comma-separated string.
  defp maybe_put_multi_select(map, _key, nil), do: map
  defp maybe_put_multi_select(map, _key, ""), do: map

  defp maybe_put_multi_select(map, key, value) when is_binary(value) do
    options =
      value
      |> String.split(",", trim: true)
      |> Enum.map(fn name -> %{name: String.trim(name)} end)

    Map.put(map, key, %{multi_select: options})
  end

  defp maybe_put_multi_select(map, _key, _), do: map

  # Build Notion properties from trade metadata.
  # Extracts metadata from the trade row and converts it to Notion property format.
  # Only includes non-nil fields to support partial metadata.
  defp build_metadata_properties(row) when is_map(row) do
    metadata = Map.get(row, :metadata)
    version = Map.get(row, :metadata_version) || 2

    case {metadata, version} do
      {meta, 1} when is_map(meta) and map_size(meta) > 0 ->
        build_v1_metadata_properties(meta)

      {meta, 2} when is_map(meta) and map_size(meta) > 0 ->
        build_v2_metadata_properties(meta)

      _ ->
        # No metadata
        %{}
    end
  end

  defp build_v1_metadata_properties(meta) when is_map(meta) do
    %{}
    # Status & control
    |> maybe_put_checkbox("Done?", get_meta_field(meta, :done?))
    |> maybe_put_checkbox("LostData?", get_meta_field(meta, :lost_data?))
    # Trade classification
    |> maybe_put_select("Rank", get_meta_field(meta, :rank))
    |> maybe_put_select("Setup", get_meta_field(meta, :setup))
    |> maybe_put_select("CloseTrigger", get_meta_field(meta, :close_trigger))
    # Sector and CapSize are rollups (read-only in Notion) — cannot be written back
    # Time
    |> maybe_put_select("Entry Timeslot", get_meta_field(meta, :entry_timeslot))
    # Boolean flags
    |> maybe_put_checkbox("OperationMistake?", get_meta_field(meta, :operation_mistake?))
    |> maybe_put_checkbox("FollowSetup?", get_meta_field(meta, :follow_setup?))
    |> maybe_put_checkbox("FollowStopLossManagement?", get_meta_field(meta, :follow_stop_loss_management?))
    |> maybe_put_checkbox("RevengeTrade?", get_meta_field(meta, :revenge_trade?))
    |> maybe_put_checkbox("FOMO?", get_meta_field(meta, :fomo?))
    |> maybe_put_checkbox("UnnecessaryTrade?", get_meta_field(meta, :unnecessary_trade?))
    # Comments (multi_select in Notion)
    |> maybe_put_multi_select("CloseTimeComment", get_meta_field(meta, :close_time_comment))
  end

  defp build_v2_metadata_properties(meta) when is_map(meta) do
    %{}
    # Status & control
    |> maybe_put_checkbox("Done?", get_meta_field(meta, :done?))
    |> maybe_put_checkbox("LostData?", get_meta_field(meta, :lost_data?))
    # Trade classification
    |> maybe_put_select("Rank", get_meta_field(meta, :rank))
    |> maybe_put_select("Setup", get_meta_field(meta, :setup))
    |> maybe_put_select("CloseTrigger", get_meta_field(meta, :close_trigger))
    # Sector and CapSize are rollups (read-only in Notion) — cannot be written back
    # Risk/reward metrics
    |> maybe_put_number("InitialRiskRewardRatio", to_number(get_meta_field(meta, :initial_risk_reward_ratio)))
    |> maybe_put_number("BestRiskRewardRatio", to_number(get_meta_field(meta, :best_risk_reward_ratio)))
    # Position sizing
    |> maybe_put_number("Size", to_number(get_meta_field(meta, :size)))
    |> maybe_put_select("OrderType", get_meta_field(meta, :order_type))
    # Time
    |> maybe_put_select("EntryTimeslot", get_meta_field(meta, :entry_timeslot))
    |> maybe_put_select("CloseTimeslot", get_meta_field(meta, :close_timeslot))
    # Boolean flags
    |> maybe_put_checkbox("RevengeTrade?", get_meta_field(meta, :revenge_trade?))
    |> maybe_put_checkbox("FOMO?", get_meta_field(meta, :fomo?))
    |> maybe_put_checkbox("AddSize?", get_meta_field(meta, :add_size?))
    |> maybe_put_checkbox("AdjustedRiskReward?", get_meta_field(meta, :adjusted_risk_reward?))
    |> maybe_put_checkbox("AlignWithTrend?", get_meta_field(meta, :align_with_trend?))
    |> maybe_put_checkbox("BetterRiskRewardRatio?", get_meta_field(meta, :better_risk_reward_ratio?))
    |> maybe_put_checkbox("BigPicture?", get_meta_field(meta, :big_picture?))
    |> maybe_put_checkbox("EarningReport?", get_meta_field(meta, :earning_report?))
    |> maybe_put_checkbox("FollowUpTrial?", get_meta_field(meta, :follow_up_trial?))
    |> maybe_put_checkbox("GoodLesson?", get_meta_field(meta, :good_lesson?))
    |> maybe_put_checkbox("HotSector?", get_meta_field(meta, :hot_sector?))
    |> maybe_put_checkbox("Momentum?", get_meta_field(meta, :momentum?))
    |> maybe_put_checkbox("News?", get_meta_field(meta, :news?))
    |> maybe_put_checkbox("NormalEmotion?", get_meta_field(meta, :normal_emotion?))
    |> maybe_put_checkbox("OperationMistake?", get_meta_field(meta, :operation_mistake?))
    |> maybe_put_checkbox("Overnight?", get_meta_field(meta, :overnight?))
    |> maybe_put_checkbox("OvernightInPurpose?", get_meta_field(meta, :overnight_in_purpose?))
    |> maybe_put_checkbox("SlippedPosition?", get_meta_field(meta, :slipped_position?))
    # Comments (multi_select in Notion)
    |> maybe_put_multi_select("CloseTimeComment", get_meta_field(meta, :close_time_comment))
  end

  # Helper to get field from metadata map (supports both atom and string keys)
  defp get_meta_field(meta, field) when is_map(meta) and is_atom(field) do
    Map.get(meta, field) || Map.get(meta, Atom.to_string(field))
  end
  defp get_meta_field(_, _), do: nil

  # (no date helper needed for Entry Timeslot; it's a select field now)

  # Map a datetime from the first action in the chain to a half-hour bucket label like "0930-1000".
  @doc """
  Computes the entry timeslot bucket label from a trade row's action_chain.
  Returns a string like \"09:30-10:00\" or nil.
  """
  def compute_entry_timeslot(row), do: entry_timeslot_bucket(row)

  @doc """
  Computes the close timeslot bucket label from a trade row's action_chain.
  Returns a string like \"14:30-15:00\" or nil.
  """
  def compute_close_timeslot(row), do: close_timeslot_bucket(row)

  defp entry_timeslot_bucket(row) when is_map(row) do
    case Map.get(row, :action_chain) || Map.get(row, "action_chain") do
      chain when is_map(chain) ->
        with %{} = open <- Map.get(chain, "1"),
             dt when is_binary(dt) <- Map.get(open, "datetime"),
             {:ok, entry_dt, _} <- DateTime.from_iso8601(dt) do
          bucket_for_datetime(entry_dt)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Map the close position datetime from the action chain to a half-hour bucket label.
  defp close_timeslot_bucket(row) when is_map(row) do
    case Map.get(row, :action_chain) || Map.get(row, "action_chain") do
      chain when is_map(chain) ->
        with close_key when is_binary(close_key) <- find_close_position_key(chain),
             %{} = close <- Map.get(chain, close_key),
             dt when is_binary(dt) <- Map.get(close, "datetime"),
             {:ok, close_dt, _} <- DateTime.from_iso8601(dt) do
          bucket_for_datetime(close_dt)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp bucket_for_datetime(%DateTime{} = dt) do
    # Use time in dt's current timezone; labels are 24-hour HHMM-HHMM.
    minutes = dt.hour * 60 + dt.minute
    # 09:30
    start_min = 9 * 60 + 30
    # 16:00 (exclusive)
    end_min = 16 * 60

    cond do
      minutes < start_min or minutes >= end_min ->
        nil

      true ->
        offset = minutes - start_min
        slot_index = div(offset, 30)
        slot_start = start_min + slot_index * 30
        slot_end = min(slot_start + 30, end_min)
        format_hhmm(slot_start) <> "-" <> format_hhmm(slot_end)
    end
  end

  defp format_hhmm(mins) when is_integer(mins) do
    h = div(mins, 60)
    m = rem(mins, 60)
    :io_lib.format("~2..0B~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  # --- Duration and Entry Timeslot helpers ---
  # Prefer explicit row.duration; otherwise compute from action_chain when available.
  defp row_duration_seconds(row) when is_map(row) do
    case Map.get(row, :duration) || Map.get(row, "duration") do
      n when is_integer(n) ->
        n

      n when is_float(n) ->
        trunc(n)

      _ ->
        case Map.get(row, :action_chain) || Map.get(row, "action_chain") do
          chain when is_map(chain) -> duration_from_action_chain(chain)
          _ -> nil
        end
    end
  end

  defp duration_from_action_chain(chain) when is_map(chain) do
    with %{} = open <- Map.get(chain, "1"),
         open_dt when is_binary(open_dt) <- Map.get(open, "datetime"),
         {:ok, open_iso, _} <- DateTime.from_iso8601(open_dt),
         close_key when is_binary(close_key) <- find_close_position_key(chain),
         %{} = close <- Map.get(chain, close_key),
         close_dt when is_binary(close_dt) <- Map.get(close, "datetime"),
         {:ok, close_iso, _} <- DateTime.from_iso8601(close_dt) do
      DateTime.diff(close_iso, open_iso, :second)
    else
      _ -> nil
    end
  end

  defp duration_from_action_chain(_), do: nil

  # Entry timeslot ISO helper removed; replaced by half-hour bucket select label

  defp find_close_position_key(action_chain) when is_map(action_chain) do
    action_chain
    |> Enum.find(fn {_k, action} ->
      is_map(action) and Map.get(action, "action") == "close_position"
    end)
    |> case do
      {key, _} -> key
      _ -> nil
    end
  end

  # Catch-all removed as to_number returns nil | number

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
    # Allow picking which database to list titles from; default to activity
    data_source_id = resolve_data_source_id(opts, conf, Keyword.get(opts, :source, :activity))
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

  @doc """
  List all pages in the configured Notion data source and return a map of
  title (Trademark) => page id.

  Options:
    * :data_source_id - overrides configured data source id
    * :title_property - overrides the title property name (default "Trademark")
    * :page_size - query page size for pagination (default 10000)

  Returns `{:ok, %{title => page_id}}` or `{:error, reason}`.
  """
  def list_all_trademarks_with_ids(opts \\ []) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = resolve_data_source_id(opts, conf, Keyword.get(opts, :source, :activity))
    title_prop = Keyword.get(opts, :title_property, conf[:title_property] || "Trademark")
    page_size = Keyword.get(opts, :page_size, 10000)

    if is_nil(data_source_id) do
      {:error, :missing_data_source_id}
    else
      case Client.retrieve_database(data_source_id) do
        {:ok, resp} ->
          case extract_pages_from_db_response(resp) do
            {:ok, pages} ->
              {:ok, build_title_id_map(pages, title_prop)}

            {:error, _} ->
              with {:ok, pages} <- paginate_all_pages(data_source_id, page_size) do
                {:ok, build_title_id_map(pages, title_prop)}
              end
          end

        {:error, _reason} ->
          with {:ok, pages} <- paginate_all_pages(data_source_id, page_size) do
            {:ok, build_title_id_map(pages, title_prop)}
          end
      end
    end
  end

  @doc """
  List all pages in the Ticker Details data source and return a map of
  ticker symbol (title) => page id.

  Returns `{:ok, %{"AAPL" => page_id, ...}}` or `{:error, reason}`.
  """
  def list_all_ticker_ids(opts \\ []) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = Keyword.get(opts, :data_source_id, conf[:ticker_details_data_source_id])

    if is_nil(data_source_id) do
      {:error, :missing_ticker_details_data_source_id}
    else
      with {:ok, pages} <- paginate_all_pages(data_source_id, 10000) do
        {:ok, build_title_id_map(pages, "Ticker")}
      end
    end
  end

  @doc """
  List all pages in the Market Daily data source and return a map of
  date string (title) => page id.

  Returns `{:ok, %{"2026-02-21" => page_id, ...}}` or `{:error, reason}`.
  """
  def list_all_date_ids(opts \\ []) do
    conf = Application.get_env(:journalex, __MODULE__, [])
    data_source_id = Keyword.get(opts, :data_source_id, conf[:market_daily_data_source_id])

    if is_nil(data_source_id) do
      {:error, :missing_market_daily_data_source_id}
    else
      with {:ok, pages} <- paginate_all_pages(data_source_id, 10000) do
        {:ok, build_title_id_map(pages, "Date")}
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

  defp build_title_id_map(pages, title_prop) when is_list(pages) do
    Enum.reduce(pages, %{}, fn page, acc ->
      title = extract_title(page, title_prop)
      id = Map.get(page, "id")

      if is_binary(title) and title != "" and is_binary(id) and id != "" do
        Map.put_new(acc, title, id)
      else
        acc
      end
    end)
  end

  # --- Data source resolution ---
  # Centralized resolver to pick the right Notion database ID depending on the context.
  # Priority: explicit opts[:data_source_id] > context-specific configured ids > generic :data_source_id
  defp resolve_data_source_id(opts, conf, kind) do
    case Keyword.get(opts, :data_source_id) do
      id when is_binary(id) and id != "" ->
        id

      _ ->
        case kind do
          :trades ->
            conf[:trades_data_source_id] || conf[:activity_statements_data_source_id] ||
              conf[:data_source_id]

          :activity ->
            conf[:activity_statements_data_source_id] || conf[:data_source_id]

          other when other in ["trades", :trade] ->
            conf[:trades_data_source_id] || conf[:activity_statements_data_source_id] ||
              conf[:data_source_id]

          _ ->
            conf[:activity_statements_data_source_id] || conf[:data_source_id]
        end
    end
  end
end

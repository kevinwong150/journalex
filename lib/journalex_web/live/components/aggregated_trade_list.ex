defmodule JournalexWeb.AggregatedTradeList do
	@moduledoc """
	Function components for rendering a generic Aggregated Trade list table.

	This component is data-source agnostic: pass any list of aggregated trade
	items (not tied to a specific ticker). Each item can be a map with fields
	like:
		- :label | :group | :date | :datetime | :id (for display label)
		- :winrate (fraction 0..1 or percent 0..100)
		- :close_positive_count and :close_count OR :wins_count and :trades_count
		- :close_trades (list of trade maps, each with :realized_pl and optional :datetime)
		- :realized_pl (number | Decimal | string)
		- :days_traded | :dates (list)

	Usage:

		<JournalexWeb.AggregatedTradeList.aggregated_trade_list items={@items} />
	"""

	use JournalexWeb, :html

	attr :items, :list,
		required: true,
		doc:
			"List of aggregated trade items. Each item may include realized_pl, winrate/counts, and date/label info"

	attr :id, :string, default: nil, doc: "Optional DOM id for the table container"
	attr :class, :string, default: nil, doc: "Optional extra CSS classes for the container"

	def aggregated_trade_list(assigns) do
		~H"""
		<div class={Enum.join(Enum.reject(["overflow-x-auto", @class], &is_nil/1), " ")} id={@id}>
			<%= if is_list(@items) and length(@items) > 0 do %>
				<table class="min-w-full divide-y divide-gray-200">
					<thead class="bg-gray-100">
						<tr>
							<th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Group</th>
							<th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Winrate</th>
							<th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Wins</th>
							<th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Close Trades</th>
							<th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Days</th>
							<th class="px-4 py-2 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Realized P/L</th>
						</tr>
					</thead>
					<tbody class="bg-white divide-y divide-gray-200">
						<%= for item <- @items do %>
							<% {iwins, itotal} = row_trade_counts(item) %>
							<tr class="hover:bg-blue-50 transition-colors">
								<td class="px-4 py-2 whitespace-nowrap text-sm text-gray-900">{item_label(item)}</td>
								<td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">{format_winrate(per_row_winrate(item))}</td>
								<td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">{format_count(iwins)}</td>
								<td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">{format_count(itotal)}</td>
								<td class="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-900">{format_count(row_days_traded(item))}</td>
								<td class={"px-4 py-2 whitespace-nowrap text-sm text-right #{pl_class_amount(to_float(Map.get(item, :realized_pl)))}"}>{format_amount(Map.get(item, :realized_pl))}</td>
							</tr>
						<% end %>
					</tbody>
				</table>
			<% else %>
				<div class="text-sm text-gray-500">No aggregated trades available.</div>
			<% end %>
		</div>
		"""
	end

	# Local helpers (duplicated for component independence). These mirror the
	# helpers used in ActivityStatementSummary for consistent formatting.
	defp pl_class_amount(n) when is_number(n) do
		cond do
			n < 0 -> "text-red-600"
			n > 0 -> "text-green-600"
			true -> "text-gray-900"
		end
	end

	defp pl_class_amount(nil), do: "text-gray-900"

	defp format_amount(nil), do: "0.00"
	defp format_amount(n) when is_number(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)
	defp format_amount(%Decimal{} = d), do: d |> Decimal.to_float() |> format_amount()

	defp format_amount(bin) when is_binary(bin) do
		case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
			{n, _} -> format_amount(n)
			:error -> "0.00"
		end
	end

	defp format_winrate(val) do
		cond do
			is_nil(val) -> "-"
			match?(%Decimal{}, val) -> val |> Decimal.to_float() |> format_winrate_number()
			is_binary(val) ->
				cleaned = val |> String.replace([",", "%"], "") |> String.trim()
				case Float.parse(cleaned) do
					{n, _} -> format_winrate_number(n)
					:error -> "-"
				end
			is_number(val) -> format_winrate_number(val)
			true -> "-"
		end
	end

	defp format_winrate_number(n) when is_number(n) do
		pct = if n <= 1.0, do: n * 100.0, else: n * 1.0
		:erlang.float_to_binary(pct, decimals: 2) <> "%"
	end

	defp format_count(nil), do: "0"
	defp format_count(n) when is_integer(n), do: Integer.to_string(n)
	defp format_count(n) when is_number(n), do: n |> trunc() |> Integer.to_string()
	defp format_count(%Decimal{} = d), do: d |> Decimal.to_integer() |> Integer.to_string()

	defp format_count(bin) when is_binary(bin) do
		case Integer.parse(String.trim(bin)) do
			{i, _} -> Integer.to_string(i)
			:error -> "0"
		end
	end

	defp per_row_winrate(row) when is_map(row) do
		case row_trade_counts(row) do
			{wins, total} when is_integer(wins) and is_integer(total) and total > 0 ->
				wins / total

			_ ->
				case Map.get(row, :winrate) do
					nil -> nil
					v -> to_fraction(v)
				end
		end
	end

	defp row_trade_counts(row) do
		cond do
			is_integer(Map.get(row, :close_positive_count)) and is_integer(Map.get(row, :close_count)) ->
				{Map.get(row, :close_positive_count), Map.get(row, :close_count)}

			is_integer(Map.get(row, :wins_count)) and is_integer(Map.get(row, :trades_count)) ->
				{Map.get(row, :wins_count), Map.get(row, :trades_count)}

			is_list(Map.get(row, :close_trades)) ->
				trades = Map.get(row, :close_trades)
				total = length(trades)
				wins = trades |> Enum.count(fn t -> to_float(Map.get(t, :realized_pl)) > 0.0 end)
				{wins, total}

			not is_nil(Map.get(row, :realized_pl)) ->
				{if(to_float(Map.get(row, :realized_pl)) > 0.0, do: 1, else: 0), 1}

			true ->
				total = Map.get(row, :close_count) || Map.get(row, :trades_count)
				winrate = Map.get(row, :winrate)

				cond do
					is_integer(total) and total > 0 and not is_nil(winrate) ->
						frac = to_fraction(winrate) || 0.0
						wins = round(frac * total)
						{wins, total}

					true ->
						{nil, nil}
				end
		end
	end

	defp row_days_traded(row) do
		case Map.get(row, :days_traded) do
			n when is_integer(n) and n >= 0 ->
				n

			_ ->
				cond do
					is_list(Map.get(row, :dates)) ->
						Map.get(row, :dates) |> Enum.uniq() |> length()

					is_list(Map.get(row, :close_trades)) ->
						Map.get(row, :close_trades)
						|> Enum.map(&date_only(Map.get(&1, :datetime)))
						|> Enum.reject(&is_nil/1)
						|> Enum.uniq()
						|> length()

					not is_nil(Map.get(row, :datetime)) or not is_nil(Map.get(row, :date)) ->
						1

					true ->
						Map.get(row, :days) || 0
				end
		end
	end

	defp date_only(nil), do: nil
	defp date_only(%DateTime{} = dt), do: Date.to_iso8601(DateTime.to_date(dt))
	defp date_only(%NaiveDateTime{} = ndt), do: Date.to_iso8601(NaiveDateTime.to_date(ndt))

	defp date_only(
				 <<y::binary-size(4), "-", m::binary-size(2), "-", d::binary-size(2), _::binary>>
			 ),
			 do: y <> "-" <> m <> "-" <> d

	defp date_only(<<y::binary-size(4), m::binary-size(2), d::binary-size(2)>>),
		do: y <> "-" <> m <> "-" <> d

	defp date_only(bin) when is_binary(bin) do
		case String.split(bin) do
			[date | _] -> date_only(date)
			_ -> nil
		end
	end

	defp to_fraction(nil), do: nil
	defp to_fraction(%Decimal{} = d), do: d |> Decimal.to_float() |> to_fraction()

	defp to_fraction(bin) when is_binary(bin) do
		cleaned = bin |> String.replace([",", "%"], "") |> String.trim()

		case Float.parse(cleaned) do
			{n, _} -> to_fraction(n)
			:error -> nil
		end
	end

	defp to_fraction(n) when is_number(n) do
		frac = if n <= 1.0, do: n * 1.0, else: n / 100.0

		frac
		|> max(0.0)
		|> min(1.0)
	end

	defp to_float(nil), do: 0.0
	defp to_float(n) when is_number(n), do: n * 1.0
	defp to_float(%Decimal{} = d), do: Decimal.to_float(d)

	defp to_float(bin) when is_binary(bin) do
		case Float.parse(String.replace(bin, ",", "") |> String.trim()) do
			{n, _} -> n * 1.0
			:error -> 0.0
		end
	end

	defp item_label(item) when is_map(item) do
		cond do
			is_binary(Map.get(item, :label)) -> Map.get(item, :label)
			is_binary(Map.get(item, :group)) -> Map.get(item, :group)
			is_binary(Map.get(item, :date)) -> Map.get(item, :date)
			not is_nil(Map.get(item, :datetime)) -> date_only(Map.get(item, :datetime)) || "-"
			is_binary(Map.get(item, :id)) -> Map.get(item, :id)
			true -> "-"
		end
	end
end

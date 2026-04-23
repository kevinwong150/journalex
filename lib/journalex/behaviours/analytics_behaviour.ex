defmodule Journalex.AnalyticsBehaviour do
  @moduledoc """
  Behaviour for the Analytics context, enabling Mox-based testing in LiveView tests.
  """

  @callback kpi_summary(keyword()) :: %{
              total_r: float(),
              win_rate: float(),
              trade_count: integer(),
              avg_r: float(),
              best_r: float(),
              worst_r: float(),
              profit_factor: float(),
              expectancy: float()
            }

  @callback equity_curve(keyword()) :: [{Date.t(), float()}]

  @callback calendar_heatmap(integer(), keyword()) :: [{String.t(), float()}]

  @callback breakdown_by_dimension(atom(), keyword()) ::
              [{String.t(), float(), float(), integer()}]

  @callback long_vs_short(keyword()) :: %{long: map(), short: map()}

  @callback flags_impact(keyword()) ::
              [{String.t(), float(), float(), integer(), integer()}]

  @callback rr_analysis(keyword()) :: %{
              histogram_bins: list(),
              scatter_data: list(),
              expectancy: float(),
              fulfillment_rate: float()
            }

  @callback time_heatmap(atom(), keyword()) ::
              [{String.t(), String.t(), float()}]

  @callback day_of_week_breakdown(keyword()) ::
              [{String.t(), float(), integer(), integer()}]

  @callback monthly_breakdown(keyword()) ::
              [{String.t(), float(), integer(), integer()}]

  @callback scorecard_periods(atom(), keyword()) :: [
              %{
                period: String.t(),
                count: integer(),
                win_pct: float(),
                total_r: float(),
                avg_r: float(),
                top_rank: String.t() | nil,
                top_flag: String.t() | nil
              }
            ]

  @callback streak_data(keyword()) :: %{
              current_streak: integer(),
              max_win_streak: integer(),
              max_loss_streak: integer(),
              per_trade_sequence: [String.t()]
            }

  @callback ticker_summary(keyword()) :: [
              %{
                ticker: String.t(),
                count: integer(),
                win_rate: float(),
                total_r: float(),
                avg_r: float(),
                last_date: Date.t() | nil
              }
            ]

  @callback available_versions() :: [integer()]
end

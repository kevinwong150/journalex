defmodule Journalex.SettingsBehaviour do
  @moduledoc """
  Behaviour for the Settings module, enabling Mox-based testing.
  Only includes functions called by the upload-result LiveView.
  """

  @callback get_summary_period_value() :: integer()
  @callback get_summary_period_unit() :: String.t()
  @callback get_filter_visible_weeks() :: integer()
  @callback get_activity_page_size() :: integer()
end

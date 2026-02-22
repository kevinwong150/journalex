defmodule Journalex.Settings do
  use Ecto.Schema
  import Ecto.Changeset
  alias Journalex.Repo

  @moduledoc """
  Key-value settings store backed by the `settings` database table.

  DB wins at runtime. Application config / env vars serve as the
  fallback/seed when a key has not been persisted to the DB yet.

  Usage:
    Settings.get("my_key", "fallback")
    Settings.put("my_key", "value")
    Settings.get_default_metadata_version()
    Settings.set_default_metadata_version(2)
  """

  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime_usec)
  end

  # ---------------------------------------------------------------------------
  # Changeset
  # ---------------------------------------------------------------------------

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key])
    |> validate_length(:key, min: 1, max: 255)
    |> unique_constraint(:key)
  end

  # ---------------------------------------------------------------------------
  # Generic get / put
  # ---------------------------------------------------------------------------

  @doc """
  Returns the raw string value stored for `key`, or `default` if not in DB.
  """
  def get(key, default \\ nil) when is_binary(key) do
    case Repo.get_by(__MODULE__, key: key) do
      %__MODULE__{value: value} -> value
      nil -> default
    end
  end

  @doc """
  Upserts the setting for `key` with the given `value`.
  Returns `{:ok, setting}` or `{:error, changeset}`.
  """
  def put(key, value) when is_binary(key) do
    string_value = to_string(value)

    case Repo.get_by(__MODULE__, key: key) do
      nil ->
        %__MODULE__{}
        |> changeset(%{key: key, value: string_value})
        |> Repo.insert()

      existing ->
        existing
        |> changeset(%{value: string_value})
        |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # Typed helpers — default_metadata_version
  # ---------------------------------------------------------------------------

  @default_metadata_version_key "default_metadata_version"

  @doc """
  Returns the default metadata version as an integer.

  Priority:
    1. DB (persisted via set_default_metadata_version/1)
    2. Application.get_env(:journalex, :default_metadata_version, 2)
  """
  def get_default_metadata_version do
    app_default = Application.get_env(:journalex, :default_metadata_version, 2)

    case get(@default_metadata_version_key) do
      nil ->
        app_default

      raw ->
        case Integer.parse(raw) do
          {n, _} -> n
          :error -> app_default
        end
    end
  end

  @doc """
  Persists the default metadata version to the DB.
  Returns `{:ok, setting}` or `{:error, changeset}`.
  """
  def set_default_metadata_version(version) when is_integer(version) do
    put(@default_metadata_version_key, Integer.to_string(version))
  end

  # ---------------------------------------------------------------------------
  # Typed helpers — auto_check_on_load
  # ---------------------------------------------------------------------------

  @auto_check_on_load_key "auto_check_on_load"

  @doc """
  Returns whether the Trades Dump page should auto-check Notion on load.

  Priority:
    1. DB (persisted via set_auto_check_on_load/1)
    2. true (default — preserves existing behaviour)
  """
  def get_auto_check_on_load do
    case get(@auto_check_on_load_key) do
      nil -> true
      "true" -> true
      _ -> false
    end
  end

  @doc """
  Persists the auto_check_on_load setting to the DB.
  Returns `{:ok, setting}` or `{:error, changeset}`.
  """
  def set_auto_check_on_load(value) when is_boolean(value) do
    put(@auto_check_on_load_key, to_string(value))
  end

  # ---------------------------------------------------------------------------
  # Typed helpers — r_size
  # ---------------------------------------------------------------------------

  @r_size_key "r_size"

  @doc """
  Returns the R size (dollar risk per trade).
  Used to auto-compute position size on losing trades: size = |realized_pl| / r_size.
  Default: 8.
  """
  def get_r_size do
    case get(@r_size_key) do
      nil -> 8.0
      raw ->
        case Float.parse(raw) do
          {n, _} -> n
          :error  -> 8.0
        end
    end
  end

  @doc """
  Persists the R size setting to the DB.
  """
  def set_r_size(value) when is_number(value) do
    put(@r_size_key, to_string(value))
  end

  # ---------------------------------------------------------------------------
  # Typed helpers — activity_page_size
  # ---------------------------------------------------------------------------

  @activity_page_size_key "activity_page_size"

  @doc """
  Returns the number of rows per page for the Activity Statement Upload Result table.
  Default: 20.
  """
  def get_activity_page_size do
    case get(@activity_page_size_key) do
      nil -> 20
      raw ->
        case Integer.parse(raw) do
          {n, _} when n > 0 -> n
          _ -> 20
        end
    end
  end

  @doc """
  Persists the activity page size setting to the DB.
  """
  def set_activity_page_size(value) when is_integer(value) and value > 0 do
    put(@activity_page_size_key, Integer.to_string(value))
  end

  # ---------------------------------------------------------------------------
  # Typed helpers — filter_visible_weeks
  # ---------------------------------------------------------------------------

  @filter_visible_weeks_key "filter_visible_weeks"

  @doc """
  Returns the number of most-recent weeks to show expanded in the day filter.
  Older weeks are collapsed behind a toggle. Default: 3.
  """
  def get_filter_visible_weeks do
    case get(@filter_visible_weeks_key) do
      nil -> 3
      raw ->
        case Integer.parse(raw) do
          {n, _} when n > 0 -> n
          _ -> 3
        end
    end
  end

  @doc """
  Persists the filter visible weeks setting to the DB.
  """
  def set_filter_visible_weeks(value) when is_integer(value) and value > 0 do
    put(@filter_visible_weeks_key, Integer.to_string(value))
  end

  # ---------------------------------------------------------------------------
  # Typed helpers — summary_period
  # ---------------------------------------------------------------------------

  @summary_period_value_key "summary_period_value"
  @summary_period_unit_key "summary_period_unit"

  @doc """
  Returns the number of periods (weeks or days) to include in the Summary table.
  Default: 3.
  """
  def get_summary_period_value do
    case get(@summary_period_value_key) do
      nil -> 3
      raw ->
        case Integer.parse(raw) do
          {n, _} when n > 0 -> n
          _ -> 3
        end
    end
  end

  @doc """
  Persists the summary period value to the DB.
  """
  def set_summary_period_value(value) when is_integer(value) and value > 0 do
    put(@summary_period_value_key, Integer.to_string(value))
  end

  @doc """
  Returns the period unit for the Summary table filter: "week" or "day".
  Default: "week".
  """
  def get_summary_period_unit do
    case get(@summary_period_unit_key) do
      nil -> "week"
      raw when raw in ["week", "day"] -> raw
      _ -> "week"
    end
  end

  @doc """
  Persists the summary period unit to the DB.
  """
  def set_summary_period_unit(unit) when unit in ["week", "day"] do
    put(@summary_period_unit_key, unit)
  end
end

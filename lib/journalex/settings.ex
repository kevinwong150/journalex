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
end

defmodule Journalex.Notion.DataSources do
  @moduledoc """
  Registry mapping Notion database IDs to metadata versions.

  Centralizes configuration for different Notion databases (V2, V3, etc.)
  and provides version lookup functionality.
  """

  @doc """
  Get the metadata version for a given Notion data source ID.

  Returns the version number (2, 3, etc.) or nil if not configured.

  ## Examples

      iex> DataSources.get_version("abc123...")
      2

      iex> DataSources.get_version("xyz789...")
      3
  """
  def get_version(data_source_id) when is_binary(data_source_id) do
    all_sources()
    |> Enum.find_value(fn {id, version} ->
      if id == data_source_id, do: version
    end)
  end

  @doc """
  Get the Notion data source ID for a specific metadata version.

  Returns the database ID or nil if not configured.

  ## Examples

      iex> DataSources.get_data_source_id(2)
      "abc123..."

      iex> DataSources.get_data_source_id(3)
      "xyz789..."
  """
  def get_data_source_id(version) when is_integer(version) do
    all_sources()
    |> Enum.find_value(fn {id, v} ->
      if v == version, do: id
    end)
  end

  @doc """
  Get all configured data sources as a list of {database_id, version} tuples.

  Reads from application configuration and returns all configured
  trades databases with their versions.

  ## Examples

      iex> DataSources.all_sources()
      [
        {"abc123...", 2},
        {"xyz789...", 3}
      ]
  """
  def all_sources do
    config = Application.get_env(:journalex, Journalex.Notion, [])

    [
      {Keyword.get(config, :trades_v2_data_source_id), 2},
      {Keyword.get(config, :trades_v3_data_source_id), 3}
      # Add more versions here as they're created
    ]
    |> Enum.reject(fn {id, _version} -> is_nil(id) end)
  end

  @doc """
  Get the configured V2 data source ID.

  Falls back to the generic trades_data_source_id if V2-specific is not set.
  """
  def v2_data_source_id do
    config = Application.get_env(:journalex, Journalex.Notion, [])

    Keyword.get(config, :trades_v2_data_source_id) ||
      Keyword.get(config, :trades_data_source_id)
  end

  @doc """
  Check if a data source ID is configured.
  """
  def configured?(data_source_id) when is_binary(data_source_id) do
    get_version(data_source_id) != nil
  end

  @doc """
  List all available versions that have configured data sources.
  """
  def available_versions do
    all_sources()
    |> Enum.map(fn {_id, version} -> version end)
    |> Enum.sort()
  end
end

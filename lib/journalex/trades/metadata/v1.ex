defmodule Journalex.Trades.Metadata.V1 do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  V1 metadata schema for trades - original Notion structure.

  This represents the first version of trade metadata fields.
  All fields are optional to support partial data.
  """

  @primary_key false
  embedded_schema do
    # Notion integration
    field :notion_page_id, :string

    # Status & control
    field :done?, :boolean, default: false
    field :lost_data?, :boolean, default: false

    # Trade classification
    field :rank, :string
    field :setup, :string
    field :close_trigger, :string
    field :sector, :string
    field :cap_size, :string

    # Time analysis
    field :entry_timeslot, :string

    # Trade characteristics - Boolean flags
    field :operation_mistake?, :boolean, default: false
    field :follow_setup?, :boolean, default: false
    field :follow_stop_loss_management?, :boolean, default: false
    field :revenge_trade?, :boolean, default: false
    field :fomo?, :boolean, default: false
    field :unnecessary_trade?, :boolean, default: false

    # Comments & notes
    field :close_time_comment, :string
  end

  @rank_values ["Not Setup", "C Trade", "B Trade", "A Trade"]

  @doc """
  Changeset for V1 metadata.

  All fields are optional to support partial updates.
  Validates enum values for rank and cap_size when present.
  """
  def changeset(metadata, attrs) do
    metadata
    |> cast(attrs, [
      :notion_page_id,
      # :ticker_link,
      # :date_link,
      :done?,
      :lost_data?,
      :rank,
      :setup,
      :close_trigger,
      :sector,
      :cap_size,
      :entry_timeslot,
      # :formatted_duration,
      # :win?,
      # :long_trade?,
      :operation_mistake?,
      :follow_setup?,
      :follow_stop_loss_management?,
      :revenge_trade?,
      :fomo?,
      :unnecessary_trade?,
      :close_time_comment
    ])
    |> validate_inclusion(:rank, @rank_values)
    |> validate_inclusion(:cap_size, @cap_size_values)
  end

  @doc """
  Create a new V1 metadata struct from a map.
  """
  def new(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end
end

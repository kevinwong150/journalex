defmodule Journalex.Repo.Migrations.AddMetadataToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      # JSONB field for flexible, evolving metadata structure
      # Default to empty map to support schema evolution over time
      add :metadata, :map, default: %{}, null: false

      # Tracks which version of metadata schema this trade uses (2, 3, etc.)
      # Nil means legacy V1 trades with no metadata
      add :metadata_version, :integer, null: true
    end

    # GIN index enables efficient queries on JSONB fields
    # Supports queries like: WHERE metadata->>'field' = 'value'
    # Or JSONB containment: WHERE metadata @> '{"done?": true}'
    create index(:trades, [:metadata], using: "GIN")

    # Index for filtering trades by metadata version
    create index(:trades, [:metadata_version])
  end
end

defmodule Journalex.Repo.Migrations.AddMetadataToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      # JSONB field for flexible, evolving metadata structure
      # Default to empty map to support schema evolution over time
      add :metadata, :map, default: %{}, null: false
    end

    # GIN index enables efficient queries on JSONB fields
    # Supports queries like: WHERE metadata->>'field' = 'value'
    # Or JSONB containment: WHERE metadata @> '{"done?": true}'
    create index(:trades, [:metadata], using: "GIN")
  end
end

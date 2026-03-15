defmodule Journalex.Repo.Migrations.AddGroupToPresetBlocks do
  use Ecto.Migration

  def change do
    alter table(:preset_blocks) do
      add :group, :string
    end
  end
end

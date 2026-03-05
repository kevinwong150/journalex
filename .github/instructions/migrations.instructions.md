---
applyTo: "priv/repo/migrations/**"
---

# Migration conventions — Journalex

## Always use `change/0` for reversible migrations

Use `up/0` + `down/0` only when `change/0` cannot express the reversal.

## New tables always include `timestamps()`

```elixir
def change do
  create table(:my_table) do
    add :ticker, :string, null: false
    add :metadata, :map   # stored as jsonb in Postgres

    timestamps()
  end
end
```

## Column naming rules

| Pattern | Rule |
|---|---|
| Boolean columns | Plain snake_case in DB (e.g. `done`, `is_active`) — the `?` suffix is Elixir-only |
| JSONB | Use `:map` type |
| Datetimes | Use `:utc_datetime_usec` |

## Add a GIN index for queryable JSONB columns

```elixir
create index(:trades, [:metadata], using: :gin)
```

## Unique indexes

Prefer `create unique_index` over `unique: true` on the column — gives friendlier Ecto errors:

```elixir
create unique_index(:settings, [:key])
```

## Ports

Never hardcode `5432`. Dev DB is on host port `6543`, test DB on `6544`.

## After the migration

Update the matching Ecto schema in `lib/journalex/` — add the field to the schema block and to the `changeset/2` cast list.

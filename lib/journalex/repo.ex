defmodule Journalex.Repo do
  use Ecto.Repo,
    otp_app: :journalex,
    adapter: Ecto.Adapters.Postgres
end

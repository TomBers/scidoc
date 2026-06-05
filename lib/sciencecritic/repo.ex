defmodule Sciencecritic.Repo do
  use Ecto.Repo,
    otp_app: :sciencecritic,
    adapter: Ecto.Adapters.Postgres
end

defmodule Sciencecritic.Repo do
  use Ecto.Repo,
    otp_app: :sciencecritic,
    adapter: Ecto.Adapters.SQLite3
end

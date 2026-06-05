import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
test_database_url = System.get_env("TEST_DATABASE_URL")
test_database_password = System.get_env("TEST_DATABASE_PASSWORD") || System.get_env("PGPASSWORD")

repo_config =
  if test_database_url do
    [url: test_database_url]
  else
    base_config = [
      username: System.get_env("TEST_DATABASE_USER") || "postgres",
      hostname: System.get_env("TEST_DATABASE_HOST") || "localhost",
      database: "sciencecritic_test#{System.get_env("MIX_TEST_PARTITION")}",
      port: String.to_integer(System.get_env("TEST_DATABASE_PORT") || "5432")
    ]

    if test_database_password do
      Keyword.put(base_config, :password, test_database_password)
    else
      base_config
    end
  end

config :sciencecritic,
       Sciencecritic.Repo,
       repo_config ++
         [
           pool_size: 5,
           pool: Ecto.Adapters.SQL.Sandbox
         ]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sciencecritic, SciencecriticWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CN9BxomVv8UyoDd/3S2L34HZJy58N1LedE7rFbdVYjH2UUHmemVyZKSL9vjqoOPD",
  server: false

# In test we don't send emails
config :sciencecritic, Sciencecritic.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

config :sciencecritic, paper_qa_disable_llm: true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

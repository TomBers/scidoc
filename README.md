# Sciencecritic

ScienceCritic is a Phoenix prototype arguing that scientific papers should be distributed as semantic document graphs with high-quality renderings, not as isolated PDFs.

## Local development

* Run `mix deps.get` to install dependencies
* Set the Supabase database password:

  ```bash
  export SUPABASE_DB_PASSWORD='<supabase-password>'
  ```

  Local development uses Supabase Postgres at `db.rztgovegfhguftbnwopd.supabase.co:6543`, database `postgres`, user `postgres`, SSL enabled, IPv6 enabled, and unnamed prepared statements for the pooler. The password remains an environment variable so it is not committed.
* Run `mix ecto.migrate` to create/update the Supabase tables. Avoid `mix ecto.create` against Supabase because the `postgres` database already exists and is managed by Supabase.
* Build the generated Attention paper HTML with `mix papers.build attention` if needed
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Render deployment notes

Set these environment variables:

```text
MIX_ENV=prod
PHX_HOST=<your-render-hostname>
SECRET_KEY_BASE=<output of mix phx.gen.secret>
DATABASE_URL=<supabase-pooler-connection-string>
POOL_SIZE=5
```

For Render + Supabase, prefer Supabase's IPv4-compatible Supavisor transaction pooler connection string rather than the direct `db.<project-ref>.supabase.co` host. The direct Supabase database host may be IPv6-only, which can cause release migrations to time out on Render while waiting for a database connection.

The Supabase pooler URL usually looks like:

```text
postgresql://postgres.<project-ref>:<url-encoded-password>@<pooler-host>.pooler.supabase.com:6543/postgres
```

If you intentionally use an IPv6-only database host in production, also set `ECTO_IPV6=true`. Optional queue settings are available as `DB_QUEUE_TARGET` and `DB_QUEUE_INTERVAL` in milliseconds.

Use this build command:

```bash
./bin/render-build
```

Use this start command:

```bash
./bin/render-start
```

The scripts build and run a Phoenix release:

```bash
# bin/render-build
mix deps.get --only prod
mix assets.setup
mix compile
mix assets.deploy
mix release --overwrite

# bin/render-start
_build/prod/rel/sciencecritic/bin/migrate
exec _build/prod/rel/sciencecritic/bin/server
```

Why:

* `mix phx.digest` only digests files that already exist; it does not build `assets/css/app.css` or `assets/js/app.js`.
* `mix assets.deploy` runs Tailwind, esbuild, and `phx.digest`, which produces `priv/static/cache_manifest.json` for production static serving.
* `mix release` packages the compiled app so Render does not need to start the service through Mix.
* `DATABASE_URL` points the release at Supabase Postgres; do not commit the password to source control.
* `bin/render-start` runs the release migration command before the server starts so tables such as `paper_selections` exist.
* The GitHub repo can be named `scidoc` while the Phoenix/OTP app remains `:sciencecritic`; those names do not need to match.

## Useful commands

```bash
mix papers.build attention
mix assets.build
mix precommit
```

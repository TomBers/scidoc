# Sciencecritic

ScienceCritic is a Phoenix prototype arguing that scientific papers should be distributed as semantic document graphs with high-quality renderings, not as isolated PDFs.

## Local development

* Run `mix setup` to install and setup dependencies
* Build the generated Attention paper HTML with `mix papers.build attention` if needed
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Render deployment notes

Set these environment variables:

```text
MIX_ENV=prod
PHX_HOST=<your-render-hostname>
SECRET_KEY_BASE=<output of mix phx.gen.secret>
DATABASE_PATH=/var/data/scidoc.db
```

For persistent SQLite storage on Render, add a persistent disk mounted at:

```text
/var/data
```

If you do not need persistence for a throwaway demo, `DATABASE_PATH=/tmp/scidoc.db` will work but the database may disappear on restart.

Use this build command:

```bash
./bin/render-build
```

Use this start command:

```bash
./bin/render-start
```

The scripts are intentionally small:

```bash
# bin/render-build
mix deps.get --only prod
mix assets.setup
mix compile
mix assets.deploy

# bin/render-start
mix ecto.create --quiet || true
mix ecto.migrate
mix phx.server
```

Why:

* `mix phx.digest` only digests files that already exist; it does not build `assets/css/app.css` or `assets/js/app.js`.
* `mix assets.deploy` runs Tailwind, esbuild, and `phx.digest`, which produces `priv/static/cache_manifest.json` for production static serving.
* SQLite must live in a writable directory. `eacces` usually means `DATABASE_PATH` points somewhere Render cannot write, or the parent directory is not on a mounted disk.
* `bin/render-start` runs `mix ecto.create --quiet || true` and `mix ecto.migrate` before the server starts so tables such as `paper_selections` exist.
* The GitHub repo can be named `scidoc` while the Phoenix/OTP app remains `:sciencecritic`; those names do not need to match.

## Useful commands

```bash
mix papers.build attention
mix assets.build
mix precommit
```

# Agent Notes

## Local Development

- Use `/Users/kaiuhl/Code/went-hiking-2026` as the active checkout for this app.
- The local development stack is intended to stay running while work happens:
  - `docker compose up -d postgres web`
  - App: `http://localhost:9292`
  - Health check: `curl http://localhost:9292/health`
- Default Docker Compose reads `compose.override.yaml`, which runs `web` with `bin/dev`, bind-mounts the checkout at `/app`, and points `DATABASE_URL` at the Compose `postgres` service.
- `bin/dev` starts Puma and `bin/dev-reload` together. Puma already has `plugin :tmp_restart` in `config/puma.rb`; the watcher touches `tmp/restart.txt` when app files change.
- `bin/dev-reload` watches Ruby/config/view files under `config`, `db/migrations`, `jobs`, `lib`, and `server`, plus top-level files such as `config.ru`, `Gemfile`, and `.env`.
- Use `docker compose logs -f web` to watch reload activity. A healthy reload log includes `Reloading Puma after changes to ...` followed by `* Restarting...`.
- Production/deploy commands should continue using explicit Compose files such as `docker compose -f compose.yaml -f compose.production.yaml ...`; that path does not include the local development override.

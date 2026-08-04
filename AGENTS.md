# Agent Notes

## Local Development

- Use `/Users/kaiuhl/Code/went-hiking-2026` as the active checkout for this app.
- Photo uploads work locally with zero config: `Storage::Local` supports the same
  direct-upload contract as S3 (`POST /uploads/direct` with an HMAC ticket), variants
  generate inline at finalize, and `/system/*` streams from `tmp/uploads` when no
  `MEDIA_BASE_URL` is configured.
- Dev email delivery falls back to an outbox: with `SES_FROM_EMAIL` unset, messages
  are written as `.eml` files to `tmp/outbox/` instead of raising. Production fails
  fast at boot if `SES_FROM_EMAIL` is missing.
- Run the test suite (the app image omits dev/test gems, so override `BUNDLE_WITHOUT`):
  `docker compose run --rm -e BUNDLE_WITHOUT= -e RACK_ENV=test -e TEST_DATABASE_URL=postgres://wenthiking:wenthiking@postgres:5432/wenthiking_test web sh -c "bundle install --quiet && bundle exec rake"`.
  This runs RSpec plus the editor's markdown round-trip harness
  (`spec/js/editor_round_trip.js`, plain node, no deps). Specs run against Postgres
  in a separate `wenthiking_test` database (created automatically on first run;
  truncated between examples) — the compose `postgres` service must be up. Host-side
  runs (mise ruby, no container) reach it on `localhost:55432`, which
  `compose.override.yaml` publishes for exactly this.
- The compose editor (`/hikes/new`, `/hikes/:slug/edit`) serializes to
  `report_markdown` + `{{ photo:ID }}` handles and must round-trip byte-identically;
  the harness above is the guard. Treat any change to `public/scripts/editor.js`
  parsing/serialization as suspect until it passes.
- Seeded dev login: `kaiuhl@gmail.com` / `password`.
- The local development stack is intended to stay running while work happens:
  - `docker compose up -d postgres web`
  - App: `http://localhost:9292`
  - Health check: `curl http://localhost:9292/health`
- Default Docker Compose reads `compose.override.yaml`, which runs `web` with `bin/dev`, bind-mounts the checkout at `/app`, and points `DATABASE_URL` at the Compose `postgres` service.
- `bin/dev` starts Puma and `bin/dev-reload` together. Puma already has `plugin :tmp_restart` in `config/puma.rb`; the watcher touches `tmp/restart.txt` when app files change.
- `bin/dev-reload` watches Ruby/config/view files under `config`, `db/migrations`, `jobs`, `lib`, and `server`, plus top-level files such as `config.ru`, `Gemfile`, and `.env`.
- Use `docker compose logs -f web` to watch reload activity. A healthy reload log includes `Reloading Puma after changes to ...` followed by `* Restarting...`.
- Production/deploy commands should continue using explicit Compose files such as `docker compose -f compose.yaml -f compose.production.yaml ...`; that path does not include the local development override.

## Product/UX Direction

- **Before designing or restyling anything, read `docs/taste.md`** — the design
  sensibility behind the 2026 refinement (typography-first, one vocabulary per
  row, optical spacing, honest states). New UI should pass its smell tests.
- Favor polished, simple UX. Secondary actions should be unobtrusive but obvious, usually as small links or compact controls near the relevant context.
- Avoid large persistent forms in primary page headers. For secondary flows such as subscribing to updates, prefer a compact trigger that opens a focused modal or similarly contained interaction.

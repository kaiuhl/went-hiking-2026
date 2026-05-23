# Went Hiking Operations

## Release

Use the guarded deploy helper from the local checkout:

```sh
bin/prod-deploy
```

The helper SSHes to Lightsail, bootstraps `/srv/went-hiking-2026` into a Git
checkout if needed, aborts if the production checkout has local changes, runs
`git pull --ff-only`, builds the `web` and `worker` images, starts Postgres, runs
`db:migrate`, starts `web`, `worker`, and `caddy`, and runs public smoke checks.

Push committed changes before deploying. The helper checks that local `HEAD`
matches the upstream branch so it does not accidentally deploy an older
`origin/main`.

Deploy a different host or branch:

```sh
WENT_HIKING_BRANCH=my-branch bin/prod-deploy
```

Skip smoke checks only when the public host is intentionally unreachable:

```sh
bin/prod-deploy --skip-smoke
```

## Host Defaults

- Public preview: `http://35.160.199.53/`
- Health check: `http://35.160.199.53/health`
- SSH user: `ubuntu`
- SSH key: `.deploy/lightsail.pem`
- App path: `/srv/went-hiking-2026`
- Git repo: `https://github.com/kaiuhl/went-hiking-2026.git`
- Git branch: `main`
- Compose files: `compose.yaml` plus `compose.production.yaml`
- Production env: `/srv/went-hiking-2026/.env`

Override defaults with environment variables:

```sh
WENT_HIKING_HOST=example.com WENT_HIKING_BASE_URL=https://example.com bin/prod-deploy
```

## Server Shell

Open a shell in the app directory:

```sh
bin/prod-shell
```

Useful server commands:

```sh
docker compose -f compose.yaml -f compose.production.yaml ps
docker compose -f compose.yaml -f compose.production.yaml logs --tail=100 web
docker compose -f compose.yaml -f compose.production.yaml logs --tail=100 worker
docker compose -f compose.yaml -f compose.production.yaml logs --tail=100 caddy
docker compose -f compose.yaml -f compose.production.yaml restart web
```

## Manual Fallback

Ansible remains the host provisioning fallback:

```sh
cd infra/ansible
ansible-playbook playbooks/deploy.yml
```

Prefer `bin/prod-deploy` for routine releases because it uses the faster
Git-checkout flow and runs deploy/smoke checks in one command.

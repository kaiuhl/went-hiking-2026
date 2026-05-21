# Went Hiking Host Automation

Ansible owns the Lightsail host configuration and app deploy flow.

## Configure Host

```sh
cd infra/ansible
ansible-playbook playbooks/site.yml
```

This installs Docker, Docker Compose v2, UFW, a 1 GB swapfile, and prepares
`/srv/went-hiking-2026`.

## Deploy App

For routine releases, prefer the repo-root helper:

```sh
bin/prod-deploy
```

It fast-forwards the production Git checkout, rebuilds the Compose stack, runs
migrations, and performs smoke checks.
See `docs/operations.md` for common production procedures.

The Ansible playbook is still available as a manual fallback. Create the release
archive first from the repo root:

```sh
COPYFILE_DISABLE=1 tar --no-xattrs \
  --exclude .deploy --exclude .git --exclude tmp --exclude log \
  --exclude vendor/bundle --exclude .DS_Store --exclude .env \
  -czf .deploy/went-hiking-2026.tar.gz .
```

Then deploy:

```sh
cd infra/ansible
ansible-playbook playbooks/deploy.yml
```

The deploy playbook extracts the release, copies `.deploy/prod.env` into place,
builds the web image, runs migrations, and starts `postgres`, `web`, and `caddy`.

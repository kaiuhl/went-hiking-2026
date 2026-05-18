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

Create the release archive first from the repo root:

```sh
COPYFILE_DISABLE=1 tar --no-xattrs \
  --exclude .deploy --exclude .git --exclude tmp --exclude log \
  --exclude vendor/bundle --exclude .DS_Store \
  -czf .deploy/went-hiking-2026.tar.gz .
```

Then deploy:

```sh
cd infra/ansible
ansible-playbook playbooks/deploy.yml
```

The deploy playbook copies `.deploy/prod.env`, extracts the release, builds the
web image, runs migrations, and starts `postgres`, `web`, and `caddy`.

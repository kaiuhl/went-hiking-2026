# Went Hiking V2 Deployment Notes

## 2026-05-18 Preview

- Public preview: `http://35.160.199.53/`
- Health check: `http://35.160.199.53/health`
- AWS account: `825135541567`
- AWS region: `us-west-2`
- Lightsail instance: `went-hiking-2026`
- Lightsail static IP: `35.160.199.53`
- Lightsail bundle: `nano_3_0` (`$5` Linux instance, IPv4-capable)
- OS image: Ubuntu 24.04
- S3 media bucket: `wenthiking-media-2026`
- CloudFront media distribution: `E2502Q91SXFH32`
- CloudFront media domain: `https://dec9ewwuufbq2.cloudfront.net`
- CloudFront OAC: `E2SDYZBFMCG2SJ`
- Server path: `/srv/went-hiking-2026`
- Services: Docker Compose `postgres`, `web`, and `caddy`
- Infrastructure as code: OpenTofu in `infra/opentofu`, Ansible in `infra/ansible`

## Smoke Checks

- `GET /health` returns `{"status":"ok"}`.
- `GET /` returns the Went Hiking V2 home page.
- `HEAD /system/images/32585/large/image.jpg` returns a `302` to `https://dec9ewwuufbq2.cloudfront.net/system/images/32585/large/image.jpg`.
- Direct S3 object URL for `system/images/32585/large/image.jpg` returns `403`.
- CloudFront URL for `system/images/32585/large/image.jpg` returns `200`.
- `docker compose -f compose.yaml -f compose.production.yaml ps` shows `postgres`, `web`, and `caddy` running.
- `bin/sync-legacy-system-to-s3 --dry-run --limit 4` lists legacy files over the recovery SSH key.
- `bin/sync-legacy-system-to-s3 --path system/images --limit 10` uploaded ten sample image objects under `s3://wenthiking-media-2026/system/images/`.
- `tofu validate` passes in `infra/opentofu`.
- `tofu plan -input=false -no-color` reports no infrastructure changes in `infra/opentofu`.
- `ansible-playbook --syntax-check playbooks/site.yml` passes from `infra/ansible`.
- `ansible-playbook --syntax-check playbooks/deploy.yml` passes from `infra/ansible`.
- CloudFront spot-checks return `200` for original, large, thumbnail, micro, and bpl variants.

## Photo Migration

- Scope: legacy trip photos only, from `/home/kylemeyer/web/wenthiking/public/system/images`.
- Destination: `s3://wenthiking-media-2026/system/images/...`.
- Access model: S3 bucket remains private, CloudFront reads via Origin Access Control, and the app redirects `/system/*` to CloudFront.
- Inventory expectation: about `203k` files and about `80 GB` under `system/images`.
- Full resumable sync started on 2026-05-18 at 05:34 PDT in detached screen session `wenthiking-photo-sync`.
- Local log: `.deploy/photo-sync.log`.
- Progress at 2026-05-18 05:38 PDT: `572` objects, `231,857,384` bytes.
- Monitor:

```sh
screen -ls
tail -f .deploy/photo-sync.log
aws s3 ls s3://wenthiking-media-2026/system/images/ --recursive --summarize
```

## Current Caveats

- The production database schema is migrated, but no legacy data has been imported.
- The S3 bucket exists with versioning enabled and public access blocked; the full trip-photo migration is in progress.
- Caddy is serving HTTP only for `wenthiking.com`/`www.wenthiking.com` until DNS is pointed at the new instance. Re-enable HTTPS after cutover.
- `EMAIL_DELIVERY=log` is set for the preview because SES sender/domain verification still needs to be completed.
- A 1 GB swapfile was added to the Lightsail instance so Docker builds fit on the nano plan.
- The current photo sync runs from the local Mac over SSH to the Linode. `caffeinate` is active inside the detached `screen` session, but the process still depends on this machine staying powered and online.

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
- Server path: `/srv/went-hiking-2026`
- Services: Docker Compose `postgres`, `web`, and `caddy`

## Smoke Checks

- `GET /health` returns `{"status":"ok"}`.
- `GET /` returns the Went Hiking V2 home page.
- `HEAD /system/images/32585/large/image.jpg` returns a `302` to `https://wenthiking-media-2026.s3.us-west-2.amazonaws.com/system/images/32585/large/image.jpg`.
- `docker compose -f compose.yaml -f compose.production.yaml ps` shows `postgres`, `web`, and `caddy` running.
- `bin/sync-legacy-system-to-s3 --dry-run --limit 4` lists legacy files over the recovery SSH key.
- `bin/sync-legacy-system-to-s3 --limit 4` uploaded and then skipped four sample avatar objects under `s3://wenthiking-media-2026/system/avatars/32585/`.

## Current Caveats

- The production database schema is migrated, but no legacy data has been imported.
- The S3 bucket exists with versioning enabled and public access blocked; legacy media has not been synced yet.
- Caddy is serving HTTP only for `wenthiking.com`/`www.wenthiking.com` until DNS is pointed at the new instance. Re-enable HTTPS after cutover.
- `EMAIL_DELIVERY=log` is set for the preview because SES sender/domain verification still needs to be completed.
- A 1 GB swapfile was added to the Lightsail instance so Docker builds fit on the nano plan.
- The legacy `public/system` directory was rechecked at about `80G`. The streaming S3 sync helper is validated on sample objects, but the full media sync has not been started.

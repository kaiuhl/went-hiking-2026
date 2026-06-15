# Went Hiking V2 Deployment Notes

## 2026-05-18 Preview

- Public preview: `https://new.wenthiking.com/`
- Health check: `https://new.wenthiking.com/health`
- Raw instance preview: `http://35.160.199.53/`
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
- Real legacy archive export completed locally from the production Rails app:
  `69,356` users, `7,989` trips, `40,542` photos, `2,439` comments, and `3,522` hearts.
- Disposable local import from that archive completed:
  `276` durable accounts, `7,989` trips, `40,416` photos, `242,496` photo variants,
  `2,320` comments, and `3,510` hearts.
- Lightsail import run `4` completed on 2026-05-18 at 09:43 PDT with the same
  counts: `276` accounts, `7,989` trips, `40,416` photos, `242,496` variants,
  `2,320` comments, and `3,510` hearts.
- Desktop Safari visual smoke test confirmed the application layout and CSS are
  loaded on the home page, a trip page, and a trip photo gallery.
- 2026-05-23 direct-upload smoke test created a temporary trip/photo, verified
  S3 browser-upload CORS for `http://35.160.199.53`, uploaded a real JPEG via
  presigned S3 POST, finalized metadata extraction, confirmed the Que worker
  generated `original`, `micro`, `thumbnail`, `bpl`, `large`, and `medium`
  variants, checked CloudFront `HEAD 200` for original/large/thumbnail, then
  removed the temporary database rows and S3 objects.

## Photo Migration

- Scope: legacy trip photos only, from `/home/kylemeyer/web/wenthiking/public/system/images`.
- Destination: `s3://wenthiking-media-2026/system/images/...`.
- Access model: S3 bucket remains private, CloudFront reads via Origin Access Control, and the app redirects `/system/*` to CloudFront.
- Inventory expectation: about `203k` files and about `80 GB` under `system/images`.
- Full resumable sync started on 2026-05-18 at 05:34 PDT in detached screen session `wenthiking-photo-sync`.
- Local log: `.deploy/photo-sync.log`.
- Progress at 2026-05-18 08:21 PDT: `25,238` objects, `9,838,732,795` bytes.
- Progress at 2026-05-18 08:49 PDT: `28,997` objects, `11,304,594,198` bytes.
- Progress at 2026-05-18 09:52 PDT: `37,487` objects, `14,782,521,920` bytes.
- Full sync completed on 2026-05-19: `205,095` files seen, `205,073` uploaded, and `22` skipped.
- Final S3 inventory: `205,095` objects and `80,299,720,161` bytes under `system/images`.
- Skip-existing confirmation completed on 2026-05-19 at 10:05 PDT: `205,095` files seen, `0` uploaded, and `205,095` skipped.
- Avatar media must also be present under `system/avatars` because the modern UI
  renders account avatars from the imported legacy user records.
- Historical logs:

```sh
tail -f .deploy/photo-sync-confirm.log
tail -f .deploy/photo-sync.log
aws s3 ls s3://wenthiking-media-2026/system/images/ --recursive --summarize
```

## SES Verification

The `wenthiking.com` SES domain identity is verified in `us-west-2`, DKIM is
successful, production access is granted, and production has
`EMAIL_DELIVERY=ses`.

## DNS Cutover

`wenthiking.com` and `www.wenthiking.com` still resolve to the old Linode IP
`173.255.199.39`; nameservers are now Cloudflare
`karsyn.ns.cloudflare.com` and `ken.ns.cloudflare.com`. Point both hostnames at
the Lightsail static IP `35.160.199.53`, then restore HTTPS in
`infra/caddy/Caddyfile`.

## Current Caveats

- The production database schema is migrated and the real legacy archive has been imported into Lightsail.
- The S3 bucket exists with versioning enabled and public access blocked; the full trip-photo archive has been synced and the skip-existing confirmation uploaded no additional objects.
- Caddy serves HTTPS for `new.wenthiking.com`. The apex `wenthiking.com`/`www.wenthiking.com`
  cutover still needs DNS pointed at the new instance and HTTPS re-enabled for
  those hostnames.
- Production auth email delivery is enabled through SES.
- Production app credentials have a narrow inline IAM policy allowing object
  read/write/delete for `system/images/*` and `system/avatars/*` in the media
  bucket so direct uploads and variant generation can use private S3.
- A 1 GB swapfile was added to the Lightsail instance so Docker builds fit on the nano plan.

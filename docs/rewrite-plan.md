# Went Hiking V2 Rewrite Checklist

This is the living implementation checklist for the Ruby 4 rewrite.

## Foundation

- [x] Create Ruby 4 project scaffold.
- [x] Add Roda, Sequel, Postgres, Puma, Caddy, Docker Compose, RSpec, and Rack::Test dependencies.
- [x] Model the app boot shape after BFP.
- [x] Add Docker and Docker Compose production skeleton.
- [x] Add Caddy reverse proxy skeleton for `wenthiking.com`.
- [x] Add OpenTofu configuration for AWS infrastructure.
- [x] Add Ansible playbooks for Lightsail host setup and app deploys.
- [x] Add CI workflow.
- [x] Add production deploy helper so the current manual tarball deploy is repeatable.

## Domain And Data

- [x] Add Sequel migrations for accounts, trips, photos, variants, comments, hearts, import runs, and Rodauth tables.
- [x] Add Sequel models with legacy ID preservation.
- [x] Add durable-content migration filter.
- [x] Add import transforms for users, trips, photos, photo variants, comments, and hearts.
- [x] Add idempotent import runner skeleton.
- [x] Test import against a real legacy database export.
- [x] Add orphan and skipped-row reports to import output.
- [x] Decide final handling for users with only legacy avatar data and no durable content.

## Auth And Accounts

- [x] Wire Rodauth into Roda.
- [x] Implement email verification.
- [x] Implement password reset and account reclaim.
- [x] Implement public signup with honeypot and signup audit records.
- [x] Send auth email through AWS SES.
- [x] Add account settings and password change screens.

## Trips, Photos, And Maps

- [x] Add canonical people, hike, and photo routes.
- [x] Add legacy route redirects for old user/hike paths.
- [x] Preserve `/system/*` media compatibility through redirect/proxy route.
- [x] Add sanitized Markdown rendering.
- [x] Add Leaflet with USGS Topo tiles.
- [x] Add responsive grayscale public UI.
- [x] Add full-page photo treatment.
- [x] Add trip photo gallery pages.
- [x] Restore homepage archive stats, map, and leaderboard UI.
- [x] Add trip create/edit forms.
- [x] Add Markdown preview editor UI.
- [x] Add baseline photo upload flow.
- [x] Add async variant generation through Que.
- [x] Add EXIF extraction into upload flow.
- [x] Replace manual hike latitude/longitude entry with a Leaflet pin picker.
- [x] Add direct-to-S3 photo upload with local/no-JS server fallback.
- [x] Polish the single-photo upload UX with preview, progress, and clearer validation.

## Dropped From V2

- [x] Retire `/map` with `410 Gone`.
- [x] Exclude forecasts from the import plan.
- [x] Exclude messages, route drawing, GPX/map layers, empty attachment tables, tracks, and shapes from the import plan.
- [x] Add compatibility redirects or gone pages for retired feature URLs.

## Testing

- [x] Unit specs for slugs.
- [x] Unit specs for Markdown sanitization.
- [x] Unit specs for S3 key generation.
- [x] Unit specs for import filtering and transforms.
- [x] Rack specs for health/version routes.
- [x] Rack specs for legacy redirects.
- [x] Rack specs for `/system/*` behavior.
- [x] Rack specs for hike pages.
- [x] Auth flow specs for entry points and public signup.
- [x] Browser/visual QA for desktop and mobile.
- [x] Add real-image upload and variant-generation regression coverage.

## Deployment

- [x] Confirm AWS CLI credentials and target region.
- [x] Create S3 media bucket.
- [x] Create private CloudFront distribution with Origin Access Control for media.
- [x] Apply S3 bucket policy allowing CloudFront-only reads under `system/images/*`.
- [x] Create Lightsail instance.
- [x] Represent S3, CloudFront, and Lightsail resources in OpenTofu.
- [x] Install Docker on Lightsail.
- [x] Represent host setup and deploy flow in Ansible.
- [x] Deploy app to Lightsail.
- [x] Run migrations on Lightsail.
- [x] Smoke-test public IP.
- [x] Record public IP and deployment notes.
- [ ] Point DNS at the new Lightsail static IP.
- [ ] Re-enable HTTPS in Caddy after DNS cutover.
- [x] Verify SES sender/domain and switch preview email delivery from log mode to SES.
- [x] Add and sample-test a streaming legacy `public/system` to S3 sync helper.
- [x] Start full legacy `system/images` photo sync to private S3.
- [x] Finish full legacy `system/images` photo sync to private S3.
- [x] Rerun photo sync and confirm skip-existing behavior after completion.
- [x] Run the import against a fresh legacy database export on Lightsail.
- [x] Run the Que worker in preview/production deploys so uploaded photo variants are generated.
- [x] Add S3 browser-upload CORS for preview, production, and local development origins.
- [x] Production-smoke a real photo upload through S3, variant generation, and CloudFront rendering.

## Current Preview Deployment

- URL: `http://35.160.199.53/`
- Health check: `http://35.160.199.53/health`
- AWS region: `us-west-2`
- Lightsail instance: `went-hiking-2026`
- Static IP: `35.160.199.53`
- S3 media bucket: `wenthiking-media-2026`
- CloudFront media domain: `https://dec9ewwuufbq2.cloudfront.net`
- Runtime: Docker Compose on Ubuntu 24.04 with `web`, `worker`, `caddy`, and `postgres`.
- Preview caveats: legacy data is imported, `/system/*` redirects to CloudFront-backed private S3 with the trip-photo archive synced, HTTPS is intentionally disabled until DNS points at the new instance, and auth emails send through SES.

## Remaining Work Inventory

Last updated: 2026-05-23.

- Add-a-hike location entry now uses a Leaflet pin picker backed by the existing `lat` and `lng` columns. Manual coordinates remain available in a compact disclosure for precision edits and no-JS fallback.
- Photo uploading now supports browser direct-to-S3 upload when S3 storage is configured: the app creates a photo record, returns a presigned S3 POST, finalizes after S3 confirms the original object exists, extracts metadata, and queues derivatives. Local storage and no-JS browsers still use the multipart server upload path.
- Photo upload has local real-image coverage: Rack upload, direct-upload initialization/finalization, image decode validation, metadata extraction, and `PhotoVariantJob` generation of `original`, `micro`, `thumbnail`, `bpl`, `large`, and `medium` variants.
- Routine deploys now start the Que `worker`, so uploaded photo derivatives can be generated in preview/production.
- Launch work still includes DNS cutover to `35.160.199.53` and re-enabling HTTPS in Caddy after DNS points at Lightsail.
- Legacy avatar media still needs an explicit final presence check under `system/avatars` because imported account avatars render from those paths.

## Add A Hike / Photo Upload Implementation Notes

### Add A Hike Map Pin

1. `server/views/hikes/form.erb` now uses a Leaflet location picker with the existing USGS Topo tile helper and marker assets.
2. The existing `lat` and `lng` inputs remain inside a collapsed manual-coordinate disclosure, so no schema or route contract changed and no-JS/precision editing still works.
3. The picker supports click/tap-to-place, drag-to-adjust, a coordinate summary, and a clear-pin control. Edit forms initialize from saved coordinates; new hikes start centered on the Pacific Northwest.
4. Server validation now rejects partial coordinates and non-finite coordinate values.
5. Coverage includes picker rendering, trip creation with coordinates, partial-coordinate rejection, and browser QA for the desktop picker flow.

### Photo Upload

1. Direct uploads use a presigned S3 POST when S3 storage is active. The server creates the pending photo/variant row, the browser posts the file to S3, and finalization confirms the object exists, extracts metadata, and queues variants.
2. The existing multipart server upload remains as a local-storage and no-JS fallback.
3. Uploaded images are decoded before server-side fallback records are committed, and direct-upload finalization rejects unreadable image data before queueing variants.
4. The form includes a selected-file preview, progress state for direct uploads, and dynamic validation errors.
5. Deploys now start the Que worker and S3 CORS allows browser POSTs from preview, production, and local development origins.

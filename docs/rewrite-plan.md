# Went Hiking V2 Rewrite Checklist

This is the living implementation checklist for the Ruby 4 rewrite.

## Foundation

- [x] Create Ruby 4 project scaffold.
- [x] Add Roda, Sequel, Postgres, Puma, Caddy, Docker Compose, RSpec, and Rack::Test dependencies.
- [x] Model the app boot shape after BFP.
- [x] Add Docker and Docker Compose production skeleton.
- [x] Add Caddy reverse proxy skeleton for `wenthiking.com`.
- [ ] Add CI workflow.
- [ ] Add production deploy helper so the current manual tarball deploy is repeatable.

## Domain And Data

- [x] Add Sequel migrations for accounts, trips, photos, variants, comments, hearts, import runs, and Rodauth tables.
- [x] Add Sequel models with legacy ID preservation.
- [x] Add durable-content migration filter.
- [x] Add import transforms for users, trips, photos, photo variants, comments, and hearts.
- [x] Add idempotent import runner skeleton.
- [ ] Test import against a real MySQL dump.
- [ ] Add orphan and skipped-row reports to import output.
- [ ] Decide final handling for users with only legacy avatar data and no durable content.

## Auth And Accounts

- [x] Wire Rodauth into Roda.
- [x] Implement email verification.
- [x] Implement password reset and account reclaim.
- [x] Implement public signup with honeypot and signup audit records.
- [x] Send auth email through AWS SES.
- [ ] Add account settings and password change screens.

## Trips, Photos, And Maps

- [x] Add canonical people, hike, and photo routes.
- [x] Add legacy route redirects for old user/hike paths.
- [x] Preserve `/system/*` media compatibility through redirect/proxy route.
- [x] Add sanitized Markdown rendering.
- [x] Add Leaflet with USGS Topo tiles.
- [x] Add responsive grayscale public UI.
- [x] Add full-page photo treatment.
- [ ] Add trip create/edit forms.
- [ ] Add Markdown preview editor UI.
- [ ] Add photo upload flow.
- [ ] Add async variant generation through Que.
- [ ] Add EXIF extraction into upload flow.

## Dropped From V2

- [x] Retire `/map` with `410 Gone`.
- [x] Exclude forecasts from the import plan.
- [x] Exclude messages, route drawing, GPX/map layers, empty attachment tables, tracks, and shapes from the import plan.
- [ ] Add compatibility redirects or gone pages for retired feature URLs.

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
- [ ] Browser/visual QA for desktop and mobile.

## Deployment

- [x] Confirm AWS CLI credentials and target region.
- [x] Create S3 media bucket.
- [x] Create Lightsail instance.
- [x] Install Docker on Lightsail.
- [x] Deploy app to Lightsail.
- [x] Run migrations on Lightsail.
- [x] Smoke-test public IP.
- [x] Record public IP and deployment notes.
- [ ] Point DNS at the new Lightsail static IP.
- [ ] Re-enable HTTPS in Caddy after DNS cutover.
- [ ] Verify SES sender/domain and switch preview email delivery from log mode to SES.
- [x] Add and sample-test a streaming legacy `public/system` to S3 sync helper.
- [ ] Run full legacy `public/system` media sync to S3.
- [ ] Run the import against a fresh legacy database dump.

## Current Preview Deployment

- URL: `http://35.160.199.53/`
- Health check: `http://35.160.199.53/health`
- AWS region: `us-west-2`
- Lightsail instance: `went-hiking-2026`
- Static IP: `35.160.199.53`
- S3 media bucket: `wenthiking-media-2026`
- Runtime: Docker Compose on Ubuntu 24.04 with `web`, `caddy`, and `postgres`.
- Preview caveats: no legacy data has been imported yet, `/system/*` redirects to the S3 bucket but the media sync is still pending, HTTPS is intentionally disabled until DNS points at the new instance, and auth emails are logging instead of sending through SES.

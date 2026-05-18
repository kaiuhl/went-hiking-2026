# Went Hiking Migration Runbook

This is a working runbook for moving `wenthiking.com` off the old Linode into a modern app deployment, with uploaded media stored in S3.

## Principles

- Treat the Linode as read-only during discovery.
- Do not store raw database credentials in docs or git.
- Preserve legacy public URLs where practical, especially `/system/...` media URLs.
- Move media directly to private S3; do not stage 80 GB of uploaded files on the Lightsail instance.
- Treat AWS infrastructure as code: OpenTofu owns cloud resources and Ansible owns host configuration/deploys.
- Import the database through a repeatable script, not manual SQL edits.
- Decide what to do with spam-like user data before the final production import.

## Source Paths

Old app:

```text
/home/kylemeyer/web/wenthiking
```

Old uploaded media:

```text
/home/kylemeyer/web/wenthiking/public/system
```

Old production database:

```text
went_hiking
```

Local rewrite workspace:

```text
/Users/kaiuhl/Code/went-hiking-2026
```

Local old GitHub checkout:

```text
/Users/kaiuhl/Code/Went-Hiking
```

## Database Dump Plan

Run the dump from the old Linode, using a temporary MySQL defaults file generated from Rails config so the password does not appear in shell history or process args.

Draft command:

```sh
cd /home/kylemeyer/web/wenthiking
umask 077

RAILS_ENV=production bundle exec rails runner '
config = ActiveRecord::Base.connection_config
File.open("/tmp/wenthiking-mysql.cnf", "w", 0600) do |f|
  f.puts "[client]"
  f.puts "user=#{config[:username]}"
  f.puts "password=#{config[:password]}" if config[:password]
  f.puts "host=#{config[:host] || "localhost"}"
  f.puts "database=#{config[:database]}"
end
'

mysqldump \
  --defaults-extra-file=/tmp/wenthiking-mysql.cnf \
  --single-transaction \
  --quick \
  --default-character-set=utf8 \
  went_hiking \
  | gzip -1 > /home/kylemeyer/went_hiking_$(date +%Y%m%d_%H%M%S).sql.gz

rm -f /tmp/wenthiking-mysql.cnf
```

The current repeatable path avoids a local MySQL dependency by exporting the
needed legacy tables through the old Rails app as JSONL:

```sh
mise exec -- bin/export-legacy-archive --output .deploy/legacy-archive-YYYYMMDD-HHMM
```

Then import that archive into the new schema:

```sh
LEGACY_ARCHIVE_PATH=.deploy/legacy-archive-YYYYMMDD-HHMM mise exec -- bin/import-legacy
```

The 2026-05-18 archive exported `69,356` users, `7,989` trips, `40,542`
photos, `2,439` comments, and `3,522` hearts. A disposable local import
produced `276` durable accounts, `7,989` trips, `40,416` photos, `242,496`
photo variants, `2,320` comments, and `3,510` hearts. Most skipped rows were
photos attached to missing legacy trip rows or comments/hearts attached to
filtered users.

Before importing into the new app, create a clean transform/import step that can:

- Map old integer IDs to new IDs while preserving old IDs where needed for legacy URLs.
- Drop or quarantine likely spam users.
- Optionally skip or archive `forecasts`.
- Preserve trip slugs/URLs and public route compatibility.
- Preserve photo metadata, captions, EXIF-derived coordinates, and original filenames.

## Infrastructure Plan

OpenTofu configuration lives in:

```text
/Users/kaiuhl/Code/went-hiking-2026/infra/opentofu
```

It owns, or is prepared to own for a fresh environment:

- Lightsail instance, static IP, static IP attachment, and public ports
- Private S3 media bucket, versioning, public access block, and bucket policy
- CloudFront Origin Access Control and distribution for private media reads

The adopted preview has two AWS provider import limitations: the existing
Lightsail static IP and public-port state cannot be imported cleanly, so those
are documented as false-by-default toggles for this preview. For a fresh
environment, set `manage_lightsail_static_ip=true` and
`manage_lightsail_public_ports=true`.

Ansible configuration lives in:

```text
/Users/kaiuhl/Code/went-hiking-2026/infra/ansible
```

It owns Docker, Docker Compose v2, UFW, swap, `/srv/went-hiking-2026`, release
archive deployment, production environment upload, migrations, and service
startup.

## Media Transfer Plan

Current S3 key layout for this run:

```text
s3://wenthiking-media-2026/system/images/<photo_id>/<style>/<filename>
```

This mirrors the old Paperclip public paths:

```text
/system/images/32585/large/image.jpg
```

The S3 bucket remains private. CloudFront distribution
`E2502Q91SXFH32` with Origin Access Control `E2SDYZBFMCG2SJ` is allowed to read
only `arn:aws:s3:::wenthiking-media-2026/system/images/*`. The preview app has:

```text
MEDIA_BASE_URL=https://dec9ewwuufbq2.cloudfront.net
```

So `/system/images/...` redirects to CloudFront while direct S3 URLs return
`403`.

Validated sample sync:

```sh
mise exec -- bin/sync-legacy-system-to-s3 --path system/images --limit 10
```

The full run is local and streaming over SSH from the Linode without staging the
photo tree locally:

```sh
screen -dmS wenthiking-photo-sync zsh -lc '
  cd /Users/kaiuhl/Code/went-hiking-2026 || exit 1
  {
    echo "started $(date) in screen session wenthiking-photo-sync"
    caffeinate -dimsu mise exec -- bin/sync-legacy-system-to-s3 --path system/images
    status=$?
    echo "finished $(date) status=$status"
    exit $status
  } >> .deploy/photo-sync.log 2>&1
'
```

Monitor:

```sh
screen -ls
tail -f .deploy/photo-sync.log
aws s3 ls s3://wenthiking-media-2026/system/images/ --recursive --summarize
```

Do not sync:

- `public/system/avatars` in the first photo-only run
- `public/system/map_layers` in the first photo-only run
- `/home/kylemeyer/web/wenthiking/log`
- `/home/kylemeyer/web/wenthiking/tmp`
- RVM directories
- Other apps under `/home/kylemeyer/web`

## Manifest Plan

Before final cutover, create a source manifest:

```sh
cd /home/kylemeyer/web/wenthiking/public
find system -type f -printf '%p\t%s\t%TY-%Tm-%Td %TH:%TM:%TS\n' > /home/kylemeyer/wenthiking-system-manifest.tsv
```

Optional checksum manifest, slower but stronger:

```sh
cd /home/kylemeyer/web/wenthiking/public
find system -type f -print0 | xargs -0 sha1sum > /home/kylemeyer/wenthiking-system-sha1.tsv
```

The checksum pass may take a long time over roughly 465k files and 79 GB.

## Rewrite Import Priorities

Core import:

- Users that have trips, comments, hearts, or admin status
- Trips
- Photos and photo metadata
- Comments
- Hearts
- Notifications only if keeping logged-in social features

Likely skip or archive:

- Forecast history, unless there is a clear product reason to keep 1.37M rows
- Empty messages
- Empty `assets`, `attachings`, `posts`, `tracks`, `gpxes`, `map_layers`, `shapes`
- Likely spam users, especially the 2025 signup spike

## Cutover Sketch

1. Build the modern app locally with an importer and S3-backed media access.
2. Take an initial database dump from Linode.
3. Sync `public/system` to S3.
4. Import into a staging database.
5. Verify representative old URLs, trip pages, image URLs, user pages, and search.
6. Freeze old app writes or put it into read-only mode.
7. Take final database dump.
8. Run final import.
9. Re-run S3 sync for deltas.
10. Deploy to Lightsail.
11. Point DNS at the new instance.
12. Keep the old Linode available but locked down until validation is complete.

## Validation Checklist

- Old `/system/images/:id/:style/:filename` URL loads.
- Old `/system/avatars/:id/:style/:filename` URL loads.
- Home page loads.
- A user page with trips loads.
- A trip with a long report and photos loads.
- A trip with GPS photo metadata displays correctly.
- Comments and hearts import with correct ownership.
- Login flow works for at least one migrated account, if accounts are kept.
- Search returns expected trip records.
- RSS route decision is explicit: supported, redirected, or intentionally removed.

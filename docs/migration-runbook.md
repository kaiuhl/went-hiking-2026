# Went Hiking Migration Runbook

This is a working runbook for moving `wenthiking.com` off the old Linode into a modern app deployment, with uploaded media stored in S3.

## Principles

- Treat the Linode as read-only during discovery.
- Do not store raw database credentials in docs or git.
- Preserve legacy public URLs where practical, especially `/system/...` media URLs.
- Move media directly to S3; do not stage 79 GB of uploaded files on the Lightsail instance.
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

Before importing into the new app, create a clean transform/import step that can:

- Map old integer IDs to new IDs while preserving old IDs where needed for legacy URLs.
- Drop or quarantine likely spam users.
- Optionally skip or archive `forecasts`.
- Preserve trip slugs/URLs and public route compatibility.
- Preserve photo metadata, captions, EXIF-derived coordinates, and original filenames.

## Media Transfer Plan

Preferred S3 key layout:

```text
s3://<bucket>/system/images/<photo_id>/<style>/<filename>
s3://<bucket>/system/avatars/<user_id>/<style>/<filename>
s3://<bucket>/system/map_layers/...
```

This mirrors the old Paperclip public paths:

```text
/system/images/32585/large/image.jpg
/system/avatars/32585/micro/photo1.jpg
```

That gives the new app a simple compatibility strategy:

- Either proxy `/system/*` to S3/CloudFront.
- Or issue permanent redirects from `/system/*` to the equivalent public object/CDN URL.
- Or serve media through app routes backed by S3 keys.

Draft direct sync from Linode to S3:

```sh
aws s3 sync \
  /home/kylemeyer/web/wenthiking/public/system \
  s3://<bucket>/system \
  --only-show-errors
```

If AWS CLI is too old or unavailable on the Linode, use a local relay:

```sh
rsync -a --partial --progress \
  -e "ssh -o HostkeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -i ~/.ssh/kylemeyer-linode-recovery -p 40000" \
  kylemeyer@wenthiking.com:/home/kylemeyer/web/wenthiking/public/system/ \
  /Volumes/<large-local-disk>/wenthiking-system/

aws s3 sync \
  /Volumes/<large-local-disk>/wenthiking-system \
  s3://<bucket>/system \
  --only-show-errors
```

Do not sync:

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

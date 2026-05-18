# Went Hiking Linode Inventory

Audit started: 2026-05-17, from local machine using SSH port 40000.

This is a living inventory of the old `wenthiking.com` Linode before migrating the app to a modern stack on AWS Lightsail with uploaded media in S3.

## Access

SSH command that works from the local machine:

```sh
ssh \
  -o HostkeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -i ~/.ssh/kylemeyer-linode-recovery \
  -p 40000 \
  kylemeyer@wenthiking.com
```

Remote user:

- User: `kylemeyer`
- UID/GID: `1000(kylemeyer) / 1001(kylemeyer)`
- Groups: `admin`, `kylemeyer`
- Passwordless sudo: no

## Server

- Hostname: `kylemeyer`
- OS: Ubuntu 10.04.2 LTS, codename `lucid`
- Kernel: `7.0.5-x86-linode193`, i686
- Disk: `/dev/sda`, 138G total, 118G used, 18G available, 87% full
- Memory: 833 MB RAM, 255 MB swap

This server is far past end-of-life. Treat it as a recovery source only.

## Running Services

Observed listening ports:

- `0.0.0.0:80`: public HTTP
- `0.0.0.0:40000`: SSH
- `127.0.0.1:3306`: MySQL
- `127.0.0.1:25`: local mail
- Multiple localhost Passenger Rack app ports for Went Hiking

Observed relevant processes:

- `nginx` master and workers
- Phusion Passenger 4.0.41
- MySQL 5.1
- Postfix
- Multiple Passenger Rack workers for `/home/kylemeyer/web/wenthiking`

Installed package clues:

- Ruby 1.8 and 1.9.1 system packages
- RVM installs including Ruby 1.9.3-p327 and Ruby 2.1.1
- MySQL 5.1
- nginx 1.4.7-era packages
- Passenger 4.0.41
- ImageMagick 6.5.7
- sqlite3

## Nginx

Went Hiking is served by `/etc/nginx/sites-enabled/wenthiking.com`, symlinked to `/etc/nginx/sites-available/wenthiking.com`.

Relevant config:

```nginx
server {
        listen          80;
        server_name     www.wenthiking.com;
        rewrite         ^/(.*) http://wenthiking.com/$1 permanent;
}
server {
        listen          80;
        server_name     wenthiking.com;
        root            /home/kylemeyer/web/wenthiking/public;
        passenger_enabled       on;
        rails_env       production;
}
```

Other enabled sites on the same box:

- `caphotobooths`
- `kaiuhl.com`
- `wenthiking.com`

## Live App

Live app root:

```text
/home/kylemeyer/web/wenthiking
```

The live app root is not a git checkout. The GitHub repo was cloned locally to:

```text
/Users/kaiuhl/code/Went-Hiking
```

GitHub repo:

```text
https://github.com/kaiuhl/Went-Hiking
```

Local checkout head:

```text
3c76c50 Merge pull request #4 from notnmeyer/fix-missing-hikes
```

Live app top-level notable files and directories:

- `app/`
- `config/`
- `db/`
- `public/`
- `public/system/`
- `log/`
- `tmp/`
- `vendor/`
- `csv/`
- `wenthiking.db`
- `tumblr_template.html`

Live file snapshots captured under:

```text
/Users/kaiuhl/Code/went-hiking-2026/docs/audit/live-wenthiking
```

Captured files:

- `Gemfile`
- `Gemfile.lock`
- `app/models/photo.rb`

Diff notes:

```text
/Users/kaiuhl/Code/went-hiking-2026/docs/audit/live-vs-github.md
```

Raw `config/database.yml` was not captured into docs because it contains database credentials.

Live app size:

- App root: about 99,494,688 KB, roughly 95 GB
- `public`: about 83,148,676 KB, roughly 79 GB
- `public/system`: about 83,123,688 KB, roughly 79 GB
- `log`: about 16,306,072 KB, roughly 15.5 GB
- `tmp`: about 23,384 KB

The log directory should not be migrated as application data. `log/production.log` alone is about 16 GB.

## Live vs GitHub Differences

Some live files differ from the GitHub checkout.

MD5 comparisons:

| File | Live MD5 | GitHub checkout MD5 | Same? |
| --- | --- | --- | --- |
| `Gemfile` | `a89b14be3d2ea77c3a2f719ed21d7532` | `de56f12cb0ff908d4a4446f245878807` | No |
| `Gemfile.lock` | `a3e57a17b981c2e1eeb01d1716cfa435` | `139ed8d8f1db3863ec3d9f1e4eb3b7b6` | No |
| `app/models/photo.rb` | `b140810a5872be83964d14526c8f31f4` | `af0e517f51a1ff601c46a35a77e828ba` | No |
| `app/models/user.rb` | `746a61be635bbaa42a017c2ef1053ad0` | `746a61be635bbaa42a017c2ef1053ad0` | Yes |
| `config/routes.rb` | `b61ebb579731051b23f47215ae03f537` | `b61ebb579731051b23f47215ae03f537` | Yes |

Known live-only model difference seen so far:

- `Photo#add_stats` on the live server calls `MiniExiftool.new(..., convert_encoding: true)`.
- The GitHub checkout calls `MiniExiftool.new(...)` without `convert_encoding: true`.

Full live copies of the differing non-secret files have been captured in `docs/audit/live-wenthiking`.

Exact live differences found so far:

- `Gemfile`: `noaa` dependency uses `https://github.com/mcordell/noaa.git` on the live server.
- GitHub checkout uses `https://github.com/rtwomey/noaa.git`.
- `Gemfile.lock`: live `noaa` revision is `275515d0f78e742deda7a8bc2e19d62bb083d510`.
- GitHub checkout `noaa` revision is `491fc1f973c9b3775be3fd2c3f205453567a6a7b`.
- `app/models/photo.rb`: live server uses `MiniExiftool.new(path, convert_encoding: true)`.
- GitHub checkout uses `MiniExiftool.new path`.

## Current Rails App Shape

Framework and runtime from GitHub/live app:

- Rails 3.2.3
- Ruby 1.9.3-p327 under RVM on the live server
- MySQL via `mysql2`
- Authlogic authentication
- Paperclip uploads
- MiniMagick and MiniExifTool for image processing and EXIF extraction
- Geokit and geospatial gems
- Delayed Job table exists, but no active Went Hiking cron was observed

Primary routes:

- `/`
- `/login`, `/logout`, `/reset_password`
- `/search`, `/advanced_search`
- `/map`
- `/about`, `/privacy_policy`, `/donate`
- `/users/:user_id/hikes`
- `/hikes`
- `/hikes/:id/photos`
- `/hikes/:id/comments`
- `/hikes/:id/hearts`
- `/forecasts`
- `/notifications`
- Legacy `/with/*path` redirects to `/users/*path`
- Legacy catch-all `/:controller(/:action(/:id))`

Primary domain models:

- `User`
- `Trip`
- `Photo`
- `Comment`
- `Heart`
- `Forecast`
- `Notification`
- `Message`
- `Route`
- `Track`
- `MapLayer`
- `Gpx`

## Database

Production database config shape:

- Adapter: `mysql2`
- Database: `went_hiking`
- Host: `localhost`
- Username: `root`

Password exists in `config/database.yml` but is intentionally not recorded here.

Production row counts from Rails:

| Table/model | Count |
| --- | ---: |
| `assets` | 0 |
| `attachings` | 0 |
| `Photo` | 40,542 |
| `Trip` | 7,989 |
| `User` | 69,356 |
| `Comment` | 2,439 |
| `Heart` | 3,522 |
| `Post` | 0 |
| `Forecast` | 1,372,839 |
| `MapLayer` | 0 |
| `Message` | 0 |
| `Notification` | 5,640 |
| `Route` | 39 |
| `Track` | 0 |
| `Gpx` | 0 |
| `DelayedJob` | 0 |

Other production stats:

- `Photo.sum(:image_file_size)`: 66,418,856,128 bytes, roughly 61.9 GiB
- `User` records with avatars: 64,998
- Photo IDs: min `1`, max `43384`
- Trip dates: 2006-05-01 through 2026-04-30
- Users with trips: 257
- Users with comments: 92
- Users with hearts: 62
- Users with avatars: 64,998
- Trips with reports: 6,096
- Trips with photos: 3,956
- Photos with captions: 3,152
- Photos with GPS coordinates: 10,204
- Photos without file names: 0
- Comments with bodies: 2,432
- Forecasts with a `user_id`: 72
- Unread notifications: 2,071

The `forecasts` table is huge relative to core app data. Decide whether historical forecasts are worth migrating or should be archived/dropped for the new app.

Approximate MySQL table storage from `SHOW TABLE STATUS`:

| Table | Data bytes | Index bytes |
| --- | ---: | ---: |
| `forecasts` | 1,830,813,696 | 0 |
| `users` | 34,144,256 | 1,589,248 |
| `photos` | 6,832,128 | 2,015,232 |
| `trips` | 5,783,552 | 311,296 |
| `comments` | 1,589,248 | 0 |
| `notifications` | 1,589,248 | 0 |
| `hearts` | 196,608 | 0 |
| `routes` | 65,536 | 0 |

Trip counts by hiked year:

| Year | Trips |
| --- | ---: |
| 2006 | 2 |
| 2008 | 7 |
| 2009 | 24 |
| 2010 | 115 |
| 2011 | 1,102 |
| 2012 | 1,009 |
| 2013 | 1,032 |
| 2014 | 1,097 |
| 2015 | 1,158 |
| 2016 | 517 |
| 2017 | 391 |
| 2018 | 403 |
| 2019 | 289 |
| 2020 | 256 |
| 2021 | 231 |
| 2022 | 138 |
| 2023 | 72 |
| 2024 | 64 |
| 2025 | 70 |
| 2026 | 12 |

User counts by signup year:

| Year | Users |
| --- | ---: |
| 2011 | 157 |
| 2012 | 119 |
| 2013 | 102 |
| 2014 | 53 |
| 2015 | 37 |
| 2016 | 30 |
| 2017 | 12 |
| 2018 | 7 |
| 2019 | 33 |
| 2020 | 127 |
| 2021 | 1,251 |
| 2022 | 789 |
| 2023 | 853 |
| 2024 | 173 |
| 2025 | 65,358 |
| 2026 | 255 |

Only 257 users have trips, but 65,358 users were created in 2025. That is likely spam or bot signup activity and should be investigated before importing all users into the new application.

## Uploaded Media

Media root:

```text
/home/kylemeyer/web/wenthiking/public/system
```

Observed Paperclip URL/path style:

```text
/system/:attachment/:id/:style/:filename
```

Photo image model path:

```ruby
:path => ":rails_root/public/system/:attachment/:id/:style/:filename"
:url  => "/system/:attachment/:id/:style/:filename"
```

Major media directories:

| Directory | Size |
| --- | ---: |
| `public/system/images` | about 80,369,308 KB |
| `public/system/avatars` | about 2,628,904 KB |
| `public/system/map_layers` | about 125,464 KB |

Total `public/system`:

- Files: 465,115
- Size: about 83,123,688 KB, roughly 79 GB

Photo files:

| Style | Files |
| --- | ---: |
| `images/original` | 40,582 |
| `images/micro` | 40,570 |
| `images/thumbnail` | 40,570 |
| `images/bpl` | 40,570 |
| `images/large` | 40,570 |
| `images/medium` | 2,233 |

Photo original size:

- `public/system/images/*/original/*`: about 64,961,629 KB, roughly 62 GB

Avatar files:

| Style | Files |
| --- | ---: |
| `avatars/original` | 65,001 |
| `avatars/micro` | 65,001 |
| `avatars/thumbnail` | 65,001 |
| `avatars/medium` | 65,001 |
| `avatars/bpl` | 0 |
| `avatars/large` | 0 |

Avatar original size:

- `public/system/avatars/*/original/*`: about 291,781 KB

ID directories:

- `public/system/images`: 40,567 ID directories, min `1`, max `43384`
- `public/system/avatars`: 64,998 ID directories, min `1`, max `68747`

Sample photo paths:

```text
public/system/images/32585/large/image.jpg
public/system/images/32585/original/image.jpeg
public/system/images/32585/thumbnail/image.jpg
public/system/images/32585/micro/image.jpg
public/system/images/32585/bpl/image.jpg
public/system/images/42689/original/Etna2.jpg
public/system/images/20525/original/DSC_5659.JPG
```

For S3, the safest compatibility path is to preserve object keys under `system/...`, so an old URL like `/system/images/32585/large/image.jpg` can be served by the new app or CDN without rewriting historical post content.

## Cron

No Went Hiking cron was found in the user crontab.

The only user crontab entry observed is for another app:

```cron
0,15,30,45 * * * * /bin/bash -l -c 'cd /home/kylemeyer/web/baskin && RAILS_ENV=production bundle exec rake baskin:send_event_reminders --silent'
```

## Migration Implications

Recommended data moves:

- Dump production MySQL database `went_hiking`.
- Export a manifest of `public/system` with path, size, checksum if practical, and modified time.
- Sync `public/system` to S3 preserving relative keys under `system/`.
- Do not migrate `log/production.log`.
- Decide whether to migrate `forecasts` into the primary database, archive it separately, or drop it.
- Preserve legacy route support for old public links, especially `/with/*path`, `/hikes`, `/users/:id/hikes`, and `/system/...`.

Recommended new-stack shape for a small Lightsail instance:

- Keep uploaded media on S3, not local disk.
- Run the app and database separately if budget allows. If staying on a $5 Lightsail, use the smallest viable local database and keep object storage external.
- Use a reverse proxy that can serve or redirect `/system/*` to S3/CloudFront.
- Build a deterministic import pipeline from the MySQL dump into the new schema.
- Keep original Paperclip IDs in the new data model or in a mapping table so legacy media URLs remain addressable.

## Open Questions

- Which historical features should survive the rewrite: forecasts, route drawing, GPX upload, comments, hearts, private messages, user accounts?
- Are the 69k users mostly real users, spam, or historical signups that need pruning?
- Should generated photo derivatives move to S3 as-is, or should the new app migrate originals and regenerate sizes?
- Should old `/system/...` URLs be served forever, redirected to S3, or rewritten in imported rich text?
- Should `forecasts` be archived instead of included in the live app database?
- What authentication model should replace Authlogic?

## Follow-Up Audit Tasks

- Capture full live-vs-GitHub diffs for differing non-secret files. Done in `docs/audit/live-vs-github.md`.
- Produce a database dump plan that does not expose credentials in shell history or docs. See `docs/migration-runbook.md`.
- Measure compressed database dump size.
- Create a media transfer plan and resumable S3 sync command. Initial plan is in `docs/migration-runbook.md`.
- Check for spam in `users`, `forecasts`, `comments`, and `messages`.
- Inventory current public URL patterns from access logs if needed.

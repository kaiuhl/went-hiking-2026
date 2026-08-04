# The gazetteer

Place search, hike locations, and the backfill — how the data gets in, how to
refresh it, and how to take it national. The code lives in
`lib/went_hiking/places/`; sources are configured in `config/place_datasets.yml`
(gazetteer), `config/place_manual.yml` (curated names), and `config/areas.yml`
(containing forests/wilderness/parks).

## What's in it

- **GNIS** (USGS Geographic Names): natural features — lakes, peaks, falls,
  ridges, springs. Per-state zip files; currently OR/WA/CA/ID/MT (~144k
  places). Public domain. Note: GNIS retired its Trail/Forest/Park classes in
  2021 and current files carry no variant names — trails come from USFS,
  forests/parks from the areas table, aliases from the curated file.
- **USFS trails** (EDW `TrailNFSPublish`): segment centerlines collapsed to
  one place per named trail per forest, pinned at the longest segment's
  midpoint (~5.9k PNW trails). Role-only segment names ("Return", "Boundary
  Spur") are dropped; modifier names ("… Alternate") are demoted.
- **USFS campgrounds** (EDW Recreation Opportunities): ~1.3k PNW.
- **Curated** (`config/place_manual.yml`): the names people actually type,
  ranked 80–100 so they outrank their GNIS namesakes.
- **Areas** (`config/areas.yml` → `areas` table): USFS forest boundaries for
  regions 05/06, wilderness areas by envelope, four PNW national parks.
  Boundaries live in `areas.boundary_json`, not in git; place↔area
  containment is precomputed into `place_area_matches`.

## Refreshing (dev or prod)

```bash
rake places:refresh        # import + seed_manual + refresh_areas + resolve
```

or piecemeal: `places:import`, `places:import_dataset[slug]`,
`places:seed_manual`, `places:refresh_areas`, `places:resolve[slug]`.
Downloads cache in `tmp/place_imports` and are never re-fetched while the
file exists — `rm -rf tmp/place_imports` is the refresh knob. Re-imports
upsert by slug and deactivate rows the source no longer carries; nothing is
deleted, so trip foreign keys always survive.

On the production box: `bin/prod-shell`, then run the rake task in the web
container with the production compose files.

## Backfilling trip locations

```bash
DRY_RUN=1 rake trips:backfill_locations   # print proposed names, write nothing
rake trips:backfill_locations             # write; only touches unresolved rows
FORCE=1 rake trips:backfill_locations     # also re-touch auto_* rows
```

Eyeball the dry run before the first real prod run — the distance thresholds
and type weights in `TripLocator` were tuned on dev seeds, and the plan is to
re-tune against the real ~8k trips. Rows with `location_source: "author"` are
never touched, under any flag.

## Going national

The gazetteer is config, not code:

1. `config/place_datasets.yml`: add the remaining state zips to the `gnis`
   `data_urls` (same S3 pattern), and delete the `bounds:` block from
   `usfs-trails`. Expect ~1M GNIS places (20–45 min import) and 200–400k
   trail segments (the paged download is the slow part — consider running the
   import locally and letting the page cache ride to prod, or run overnight).
2. `config/areas.yml`: add the remaining USFS regions to `usfs_forests`,
   widen (or remove) the wilderness envelope, and add NPS units. National is
   ~110 forests + ~800 wilderness + ~430 parks; the resolver holds parsed
   boundaries in memory (~200–500 MB at national scale), so run
   `places:resolve` where that fits — locally against a dump if the prod box
   can't.
3. `rake places:refresh`, then `FORCE=1 rake trips:backfill_locations`
   (force only re-touches auto rows).

Tables plus the trigram index stay under ~1 GB at national scale.

## Licensing

Every dataset row carries `license_name` (NOT NULL), `license_url`, and
`attribution_text`; place pages render the attribution. GNIS is public
domain; USFS layers are public geodata. If a source with real terms is ever
added (RIDB, OSM's ODbL), verify before enabling — that's why the column
refuses to be empty.

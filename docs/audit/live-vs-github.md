# Live vs GitHub Diff Notes

Compared live files from:

```text
/home/kylemeyer/web/wenthiking
```

against GitHub checkout:

```text
/Users/kaiuhl/Code/Went-Hiking
```

Raw live file copies are in:

```text
/Users/kaiuhl/Code/went-hiking-2026/docs/audit/live-wenthiking
```

## Gemfile

```diff
-gem 'noaa', :git => "https://github.com/rtwomey/noaa.git"
+gem 'noaa', :git => "https://github.com/mcordell/noaa.git"
```

## Gemfile.lock

```diff
 GIT
-  remote: https://github.com/rtwomey/noaa.git
-  revision: 491fc1f973c9b3775be3fd2c3f205453567a6a7b
+  remote: https://github.com/mcordell/noaa.git
+  revision: 275515d0f78e742deda7a8bc2e19d62bb083d510
   specs:
     noaa (0.2.3)
       geokit (>= 1.5.0)
```

## app/models/photo.rb

```diff
   def add_stats
-      photo = MiniExiftool.new "#{Rails.root.to_s}/public#{self.image.url(:original, false)}"
+      photo = MiniExiftool.new("#{Rails.root.to_s}/public#{self.image.url(:original, false)}", convert_encoding: true)
       self.taken_at = photo.date_time_original
```

## Migration Meaning

- Preserve the live `MiniExiftool` encoding behavior in the importer or replacement image metadata pipeline.
- The `noaa` dependency only matters if the rewrite preserves forecast functionality.
- Do not treat GitHub as the only source of truth for deployed behavior.

# frozen_string_literal: true

require "cgi"
require "json"
require "went_hiking/hike_flags"
require "went_hiking/legacy_urls"
require "went_hiking/markdown"
require "went_hiking/storage"

module ViewHelpers
  PHOTO_HANDLE_PATTERN = /\{\{\s*photo:\s*(\d+)\s*\}\}/
  TripReportRender = Struct.new(:html, :inline_photo_ids, keyword_init: true)
  LEAFLET_TILE_URL = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"
  DEFAULT_DESCRIPTION = "Plan hikes, share trip reports, map routes, and browse photos from the trail."

  def h(value)
    CGI.escape_html(value.to_s)
  end

  def markdown(value, demote_below: nil)
    @markdown ||= WentHiking::Markdown.new
    @markdown.render(value, demote_below: demote_below)
  end

  def json(value)
    JSON.generate(value)
  end

  def static_asset_path(path)
    public_path = File.join(WentHiking.root, "public", path.to_s.sub(%r{\A/+}, ""))
    return path unless File.file?(public_path)

    separator = path.include?("?") ? "&" : "?"
    "#{path}#{separator}v=#{File.mtime(public_path).to_i}"
  end

  # Rodauth sets its flash under a symbol key, but the session round-trips
  # through JSON, so by the time the message is read back the key is a string.
  # Both spellings, and a blank message is no message.
  def flash_message(key)
    return nil unless respond_to?(:flash)

    message = (flash[key] || flash[key.to_s]).to_s.strip
    message.empty? ? nil : message
  end

  def current_account
    return nil unless rodauth.logged_in?

    @current_account ||= WentHiking::Models::Account[rodauth.session_value]
  end

  def first_name(account)
    account.name.to_s.strip.split(/\s+/, 2).first || account.email.to_s.split("@").first
  end

  def date_label(value)
    return "" unless value

    value.strftime("%B %-d, %Y")
  end

  def trip_date_label(trip)
    start = trip.hiked_at
    return "" unless start

    if trip.nights.to_i.positive?
      finish = start + (trip.nights.to_i * 86_400)
      "#{start.strftime("%B %-d")} to #{finish.strftime("%B %-d, %Y")}"
    else
      start.strftime("%B %-d, %Y")
    end
  end

  # The condition flags an author tapped, as reading words in vocabulary
  # order. Empty for the twenty years of hikes that never had flags.
  def trip_condition_labels(trip)
    WentHiking::HikeFlags.all.filter_map { |flag| flag.published_for(trip[flag.key]) }
  end

  def number_label(value, unit)
    return nil if value.nil?

    formatted = format_number(value)
    "#{formatted} #{unit}"
  end

  def night_count_label(value)
    count = value.to_i
    return nil unless count.positive?

    "#{format_number(count)} #{(count == 1) ? "night" : "nights"}"
  end

  def format_number(value, precision: nil)
    number = precision ? value.to_f.round(precision) : value
    string = (number.to_f % 1).zero? ? number.to_i.to_s : number.to_s
    integer, decimal = string.split(".", 2)
    integer = integer.reverse.scan(/.{1,3}/).join(",").reverse
    [integer, decimal].compact.join(".")
  end

  # ImageMagick geometry for the fit-style variants, from PhotoVariantJob::STYLES.
  # The `>` geometries only ever shrink, and they preserve aspect ratio, so a
  # photo's own dimensions are enough to work out what came out the other side.
  PHOTO_VARIANT_BOUNDS = {
    "bpl" => [550, 900],
    "large" => [900, 1200],
    "medium" => [300, 300]
  }.freeze

  def image_url(photo, style = "large")
    resolved_photo_variant(photo, style)&.public_url || "/images/photo-placeholder.svg"
  end

  # The style asked for is not always the style served, and the dimensions have
  # to describe what actually goes down the wire.
  def resolved_photo_variant(photo, style)
    photo_variant(photo, style) || photo_variant(photo, "large") || photo_variant(photo, "original")
  end

  # Every view asks for a variant twice over — its URL, then its dimensions — so
  # the lookups are memoised for the life of the request.
  def photo_variant(photo, style)
    key = [photo.id, style.to_s]
    @photo_variants ||= {}
    return @photo_variants[key] if @photo_variants.key?(key)

    @photo_variants[key] = photo.variant(style)
  end

  def photo_dimensions(photo, style = "large")
    variant = resolved_photo_variant(photo, style)
    return nil unless variant
    return [variant.width, variant.height] if variant.width.to_i.positive? && variant.height.to_i.positive?

    width = photo.width.to_i
    height = photo.height.to_i
    return nil unless width.positive? && height.positive?
    return [width, height] if variant.style.to_s == "original"

    bounds = PHOTO_VARIANT_BOUNDS[variant.style.to_s]
    return nil unless bounds

    scale = [1.0, bounds[0] / width.to_f, bounds[1] / height.to_f].min
    [(width * scale).round, (height * scale).round]
  end

  # Reserving the box before the bytes land is what stops a gallery from
  # reflowing as it loads. Legacy rows carry no dimensions at all, so the grids
  # also reserve space with aspect-ratio and this stays an upgrade, not a
  # requirement.
  def photo_size_attributes(photo, style = "large")
    dimensions = photo_dimensions(photo, style)
    return "" unless dimensions

    %( width="#{dimensions[0]}" height="#{dimensions[1]}")
  end

  def photo_metadata_label(photo)
    [
      date_label(photo.taken_at),
      metadata_text(photo.camera_model),
      f_stop_label(photo.camera_f_stop),
      metadata_text(photo.camera_exposure),
      iso_label(photo.camera_iso)
    ].compact.reject(&:empty?).join(" · ")
  end

  # A caption when the author wrote one; the hike's name when they did not, so
  # no photo ships an empty alt attribute.
  def photo_alt(photo)
    caption = photo.caption.to_s.strip
    return caption unless caption.empty?

    trip_name = photo.trip&.name.to_s.strip
    trip_name.empty? ? "Trail photo" : "Photo from #{trip_name}"
  end

  def photo_lightbox_items(photos)
    photos.map do |photo|
      caption = photo.caption.to_s

      {
        href: photo.public_path,
        full: image_url(photo, "original"),
        thumb: image_url(photo, "large"),
        alt: photo_alt(photo),
        caption: caption,
        metadata: photo_metadata_label(photo)
      }
    end
  end

  def photo_handle(photo)
    "{{ photo:#{photo.id} }}"
  end

  def photo_editor_item(photo)
    {
      id: photo.id,
      handle: photo_handle(photo),
      caption: photo.caption.to_s,
      thumb_url: image_url(photo, "large"),
      full_url: image_url(photo, "original"),
      caption_url: "#{photo.trip.public_path}/photos/#{photo.id}/caption",
      metadata: photo_metadata_label(photo),
      # The calendar day only: the editor dates the hike from its photos, and
      # a wall-clock date is the one thing EXIF records without a timezone.
      taken_on: photo.taken_at&.to_date&.iso8601
    }
  end

  def metadata_text(value)
    text = value.to_s.strip
    text.empty? ? nil : text
  end

  def f_stop_label(value)
    number = positive_number(value)
    return nil unless number

    "f/#{format_number(number)}"
  end

  def iso_label(value)
    number = positive_number(value)
    return nil unless number

    "ISO #{format_number(number)}"
  end

  def positive_number(value)
    return nil if value.nil?

    number = Float(value)
    number.positive? ? number : nil
  rescue ArgumentError, TypeError
    nil
  end

  def trip_report_render(trip, photos, body: nil)
    report = body.nil? ? trip.report_markdown.to_s : body.to_s
    # The photo handles below cut the report into pieces that are rendered one
    # at a time, so how far headings are demoted has to be settled across the
    # whole report first. Left to the pieces, a "# Trip" before a photo and a
    # "## Day one" after it would land on the same level.
    demote_below = WentHiking::Markdown.demote_below(report)
    photos_by_id = photos.each_with_object({}) { |photo, memo| memo[photo.id] = photo }
    photo_indexes = photos.each_with_index.each_with_object({}) { |(photo, index), memo| memo[photo.id] = index }
    inline_photo_ids = []
    html = +""
    cursor = 0

    report.to_enum(:scan, PHOTO_HANDLE_PATTERN).each do
      match = Regexp.last_match
      html << markdown(report[cursor...match.begin(0)], demote_below: demote_below)

      photo_id = match[1].to_i
      photo = photos_by_id[photo_id]
      if photo && !inline_photo_ids.include?(photo_id)
        inline_photo_ids << photo_id
        html << trip_inline_photo_figure(photo, index: photo_indexes[photo_id], eager: inline_photo_ids.size == 1)
      else
        html << h(match[0])
      end

      cursor = match.end(0)
    end

    html << markdown(report[cursor..], demote_below: demote_below)
    TripReportRender.new(html: html, inline_photo_ids: inline_photo_ids)
  end

  # The first inline photo is usually the largest thing above the fold, which
  # makes it the LCP candidate: it loads eagerly at high priority and hands the
  # layout a preload hint, while everything below it stays lazy.
  def trip_inline_photo_figure(photo, index: nil, eager: false)
    if eager
      @lcp_image_url ||= image_url(photo, "large")
      loading_attrs = %( fetchpriority="high")
    else
      loading_attrs = %( loading="lazy")
    end
    caption = photo.caption.to_s
    metadata = photo_metadata_label(photo)
    figcaption = if caption.empty? && metadata.empty?
      ""
    else
      <<~HTML
        <figcaption>
          #{%(<p>#{h(caption)}</p>) unless caption.empty?}
          #{%(<p class="meta">#{h(metadata)}</p>) unless metadata.empty?}
        </figcaption>
      HTML
    end
    lightbox_attrs = index.nil? ? "" : %( data-photo-lightbox-trigger data-photo-index="#{h(index)}")

    <<~HTML
      <figure class="trip-inline-photo">
        <a href="#{h(image_url(photo, "original"))}"#{lightbox_attrs}>
          <img src="#{h(image_url(photo, "large"))}"#{photo_size_attributes(photo)} alt="#{h(photo_alt(photo))}"#{loading_attrs}>
        </a>
        #{figcaption}
      </figure>
    HTML
  end

  def trip_photo_gallery_html(photos, all_photos:, map_trip: nil)
    return "" if photos.empty?

    photo_indexes = all_photos.each_with_index.each_with_object({}) { |(photo, index), memo| memo[photo.id] = index }
    items = [trip_gallery_map_tile_html(map_trip)]
    items += photos.map do |photo|
      index = photo_indexes[photo.id] || 0
      <<~HTML
        <a href="#{h(photo.public_path)}" data-photo-lightbox-trigger data-photo-index="#{h(index)}">
          <img src="#{h(image_url(photo, "large"))}"#{photo_size_attributes(photo)} alt="#{h(photo_alt(photo))}" loading="lazy">
        </a>
      HTML
    end
    items = items.compact.join

    <<~HTML
      <section class="trip-photo-gallery" aria-label="Trip photos">
        <div class="trip-photo-grid">
          #{items}
        </div>
      </section>
    HTML
  end

  def trip_gallery_map_tile_html(trip)
    return nil unless trip&.lat && trip.lng

    <<~HTML
      <a class="trip-map-tile" href="#{h(trip.public_path)}" aria-label="#{h("#{trip.name} map")}">
        <div class="trip-map-tile-map" data-static-map data-lat="#{h(trip.lat)}" data-lng="#{h(trip.lng)}" data-title="#{h(trip.name)}" data-tile-url="#{h(leaflet_tile_url)}" aria-hidden="true"></div>
      </a>
    HTML
  end

  # A listing renders one heart button per row, and each one used to ask the
  # database for its own count (and, signed in, whether this viewer is in it).
  # Asking once for the whole page instead is the difference between two
  # queries and two hundred; anything not primed still answers for itself.
  def prime_heart_counts(trips)
    @heart_counts ||= {}
    @hearted_trip_ids ||= {}
    ids = trips.map(&:id).reject { |id| @heart_counts.key?(id) }
    return if ids.empty?

    ids.each { |id| @heart_counts[id] = 0 }
    WentHiking::Models::Heart.where(trip_id: ids).group_and_count(:trip_id).each do |row|
      @heart_counts[row[:trip_id]] = row[:count]
    end

    return unless rodauth.logged_in?

    ids.each { |id| @hearted_trip_ids[id] = false }
    WentHiking::Models::Heart
      .where(trip_id: ids, account_id: rodauth.session_value.to_i)
      .select_map(:trip_id)
      .each { |id| @hearted_trip_ids[id] = true }
  end

  def heart_count(trip)
    primed = @heart_counts && @heart_counts[trip.id]
    return primed if primed

    trip.hearts_dataset.count
  end

  def heart_button(trip)
    heart_count = heart_count(trip)
    hearted = trip_hearted_by_current_account?(trip)
    label_on = "Remove heart from #{trip.name}"
    label_off = "Heart #{trip.name}"
    label = hearted ? label_on : label_off
    button_class = ["heart-button", ("is-hearted" if hearted)].compact.join(" ")
    count_label = heart_count_label(heart_count)
    content = heart_icon_svg + %(<span class="heart-count" data-heart-count>#{h(format_number(heart_count))}</span>)

    if rodauth.logged_in?
      # data-heart-form marks this up for the no-reload enhancement in site.js.
      # Without JS the form still posts and the server redirects back.
      <<~HTML
        <form class="heart-form" action="#{h(trip.public_path)}/hearts" method="post" data-heart-form data-heart-label-on="#{h(label_on)}" data-heart-label-off="#{h(label_off)}" data-heart-count-value="#{h(heart_count)}">
          #{csrf_tag}
          <input type="hidden" name="return_to" value="#{h(return_to_path)}">
          <button class="#{h(button_class)}" type="submit" aria-label="#{h(label)}" aria-pressed="#{hearted ? "true" : "false"}" title="#{h(count_label)}">
            #{content}
          </button>
        </form>
      HTML
    else
      # The same data-heart-count-value the form carries, so the zero-count
      # hiding in site.css needs only one selector for both renderings.
      <<~HTML
        <a class="#{h(button_class)}" href="/login" aria-label="#{h("Log in to #{label.downcase}")}" title="#{h(count_label)}" data-heart-count-value="#{h(heart_count)}">
          #{content}
        </a>
      HTML
    end
  end

  # Page one keeps the bare path so the archive has one canonical URL per page
  # rather than two spellings of the first.
  def pager_path(path, params, page)
    pairs = params.reject { |_key, value| value.to_s.empty? }
    pairs = pairs.merge("page" => page) unless page.to_i <= 1
    query = pairs.map { |key, value| "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}" }.join("&")
    query.empty? ? path : "#{path}?#{query}"
  end

  def pager_range_label(pagination, noun)
    plural = (pagination.total == 1) ? noun : "#{noun}s"
    "Showing #{format_number(pagination.first_item)}&ndash;#{format_number(pagination.last_item)} of #{format_number(pagination.total)} #{plural}"
  end

  def heart_count_label(count)
    "#{format_number(count)} #{(count == 1) ? "heart" : "hearts"}"
  end

  def heart_summary(hearts)
    count = hearts.size
    "#{format_number(count)} #{(count == 1) ? "person has" : "people have"} hearted this trip."
  end

  def avatar_url(account, style = "micro")
    return nil unless account.avatar_file_name
    return account.avatar_file_name if account.avatar_file_name.match?(%r{\Ahttps?://}i)

    filename = account.legacy_user_id ? derivative_filename(account.avatar_file_name, style) : account.avatar_file_name
    key = WentHiking::S3Keys.avatar_variant_key(account_id: account.legacy_user_id || account.id, style: style, filename: filename)
    WentHiking::LegacyUrls.legacy_media_url(key)
  end

  # Every element that renders a Leaflet map asks for the tile URL, so asking
  # is what marks the page as needing Leaflet. The layout renders after the
  # view in Roda, so the flag is set by the time the <head> is built and no
  # view has to remember to declare it.
  def leaflet_tile_url
    @needs_map = true
    LEAFLET_TILE_URL
  end

  def map_required?
    @needs_map == true
  end

  # Pagination and the profile year picker produce genuinely different pages,
  # so those two parameters survive into the canonical URL; every other query
  # string (search terms, tracking junk) canonicalizes back to the bare path.
  # Page one keeps the bare path, matching the URLs the pager itself emits.
  CANONICAL_PARAMS = %w[year page].freeze

  def canonical_url
    params = request.params.slice(*CANONICAL_PARAMS).reject { |_key, value| value.to_s.empty? }
    params.delete("page") if params["page"].to_i <= 1
    query = CANONICAL_PARAMS.filter_map { |key| "#{key}=#{CGI.escape(params[key].to_s)}" if params.key?(key) }.join("&")
    absolute_url(query.empty? ? request.path : "#{request.path}?#{query}")
  end

  # The browser tab and the search result both need the site name, but a page
  # that already says it (the home page) should not stutter.
  def page_title
    title = @title.to_s.strip
    return "Went Hiking" if title.empty?

    title.include?("Went Hiking") ? title : "#{title} · Went Hiking"
  end

  def page_description
    return @description if @description

    excerpt = trip_description_excerpt
    excerpt || DEFAULT_DESCRIPTION
  end

  def social_image_alt
    photo = social_image_photo
    return photo.caption if photo && !photo.caption.to_s.empty?

    @trip ? "Photo from #{@trip.name}" : "Went Hiking"
  end

  # The default card is a known 1200x630; a trip photo answers for itself.
  def social_image_dimensions
    photo = social_image_photo
    photo ? photo_dimensions(photo, "large") : [1200, 630]
  end

  def social_image_url
    photo = social_image_photo
    return image_url(photo, "large") if photo

    absolute_url("/images/og-default.png")
  end

  def absolute_url(path)
    "#{WentHiking.public_base_url.to_s.sub(%r{/+\z}, "")}/#{path.to_s.sub(%r{\A/+}, "")}"
  end

  # One JSON-LD block per page type that has an entity worth describing: the
  # trip page is an Article at a Place, a profile is a ProfilePage, and the
  # home page declares the site and its search box. Keyed off the canonical
  # path so a photo page (which also holds @trip) does not claim to be the
  # trip's article at a second URL.
  def structured_data
    if @trip&.published? && request.path == @trip.public_path
      trip_structured_data(@trip)
    elsif @account && request.path == @account.public_path
      profile_structured_data(@account)
    elsif request.path == "/"
      website_structured_data
    end
  end

  def structured_data_json(data)
    JSON.generate(data, script_safe: true)
  end

  def direct_photo_upload_available?
    WentHiking::Storage.current.direct_upload?
  rescue
    false
  end

  def wordmark_svg(id:, class_name:)
    escaped_id = h(id)
    escaped_class = h(class_name)

    <<~SVG
      <svg class="#{escaped_class}" viewBox="0 0 560 190" role="img" aria-labelledby="#{escaped_id}-title">
        <title id="#{escaped_id}-title">Went Hiking</title>
        <defs>
          <path id="#{escaped_id}-curve" d="M -84 170 A 1800 1800 0 0 1 500 132" />
        </defs>
        <text class="logo-text logo-text-shadow">
          <textPath href="##{escaped_id}-curve" startOffset="50%" text-anchor="middle">Went Hiking</textPath>
        </text>
        <text class="logo-text logo-text-fill">
          <textPath href="##{escaped_id}-curve" startOffset="50%" text-anchor="middle">Went Hiking</textPath>
        </text>
      </svg>
    SVG
  end

  private

  def trip_structured_data(trip)
    data = {
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => trip.name,
      "url" => absolute_url(trip.public_path),
      "mainEntityOfPage" => absolute_url(trip.public_path),
      "description" => page_description,
      "author" => {
        "@type" => "Person",
        "name" => trip.account.name,
        "url" => absolute_url(trip.account.public_path)
      },
      "publisher" => {"@type" => "Organization", "name" => "Went Hiking", "url" => absolute_url("/")}
    }
    data["datePublished"] = trip.published_at.iso8601 if trip.published_at
    data["dateModified"] = trip.updated_at.iso8601 if trip.updated_at

    images = (@photos || []).first(3).map { |photo| image_url(photo, "large") }.grep(%r{\Ahttps?://})
    data["image"] = images unless images.empty?

    if trip.lat && trip.lng
      data["contentLocation"] = {
        "@type" => "Place",
        "name" => trip.name,
        "geo" => {"@type" => "GeoCoordinates", "latitude" => trip.lat.to_f, "longitude" => trip.lng.to_f}
      }
    end

    data
  end

  def profile_structured_data(account)
    person = {
      "@type" => "Person",
      "name" => account.name,
      "url" => absolute_url(account.public_path)
    }
    location = account.location.to_s.strip
    person["homeLocation"] = {"@type" => "Place", "name" => location} unless location.empty?
    avatar = avatar_url(account, "medium")
    person["image"] = avatar if avatar

    {
      "@context" => "https://schema.org",
      "@type" => "ProfilePage",
      "mainEntity" => person
    }
  end

  def website_structured_data
    {
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Went Hiking",
      "url" => absolute_url("/"),
      "potentialAction" => {
        "@type" => "SearchAction",
        "target" => {"@type" => "EntryPoint", "urlTemplate" => "#{absolute_url("/search")}?q={search_term_string}"},
        "query-input" => "required name=search_term_string"
      }
    }
  end

  def social_image_photo
    return @photo if @photo
    return nil unless @trip

    @trip.photos_dataset.order(:taken_at, :id).first
  end

  def trip_description_excerpt
    return nil unless @trip

    text = @trip.report_markdown.to_s.gsub(PHOTO_HANDLE_PATTERN, " ").gsub(/\s+/, " ").strip
    return nil if text.empty?

    (text.length > 200) ? "#{text[0, 197]}..." : text
  end

  def trip_hearted_by_current_account?(trip)
    return false unless rodauth.logged_in?

    primed = @hearted_trip_ids && @hearted_trip_ids[trip.id]
    return primed unless primed.nil?

    trip.hearts_dataset.where(account_id: rodauth.session_value.to_i).any?
  end

  def return_to_path
    query = request.query_string.to_s
    query.empty? ? request.path_info : "#{request.path_info}?#{query}"
  end

  # The fill is driven by the .is-hearted class rather than a fill attribute so
  # that the optimistic toggle in site.js only has to move one class.
  def heart_icon_svg
    <<~SVG
      <svg class="heart-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path d="M12 20s-7-4.35-9.33-9.03C1.35 8.33 2.2 5.18 4.93 4.24 7.02 3.52 9.14 4.32 10.5 6.06L12 8l1.5-1.94c1.36-1.74 3.48-2.54 5.57-1.82 2.73.94 3.58 4.09 2.26 6.73C19 15.65 12 20 12 20Z"></path>
      </svg>
    SVG
  end

  def derivative_filename(filename, style)
    return filename if style == "original"

    "#{File.basename(filename, ".*")}.jpg"
  end
end

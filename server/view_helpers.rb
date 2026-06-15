# frozen_string_literal: true

require "cgi"
require "json"
require "went_hiking/legacy_urls"
require "went_hiking/markdown"
require "went_hiking/storage"

module ViewHelpers
  PHOTO_HANDLE_PATTERN = /\{\{\s*photo:\s*(\d+)\s*\}\}/
  TripReportRender = Struct.new(:html, :inline_photo_ids, keyword_init: true)

  def h(value)
    CGI.escape_html(value.to_s)
  end

  def markdown(value)
    @markdown ||= WentHiking::Markdown.new
    @markdown.render(value)
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

  def image_url(photo, style = "large")
    variant = photo.variant(style) || photo.variant("large") || photo.variant("original")
    variant&.public_url || "/images/photo-placeholder.svg"
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

  def photo_lightbox_items(photos)
    photos.map do |photo|
      caption = photo.caption.to_s

      {
        href: photo.public_path,
        full: image_url(photo, "original"),
        thumb: image_url(photo, "large"),
        alt: caption,
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
      metadata: photo_metadata_label(photo)
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
    photos_by_id = photos.each_with_object({}) { |photo, memo| memo[photo.id] = photo }
    photo_indexes = photos.each_with_index.each_with_object({}) { |(photo, index), memo| memo[photo.id] = index }
    inline_photo_ids = []
    html = +""
    cursor = 0

    report.to_enum(:scan, PHOTO_HANDLE_PATTERN).each do
      match = Regexp.last_match
      html << markdown(report[cursor...match.begin(0)])

      photo_id = match[1].to_i
      photo = photos_by_id[photo_id]
      if photo && !inline_photo_ids.include?(photo_id)
        inline_photo_ids << photo_id
        html << trip_inline_photo_figure(photo, index: photo_indexes[photo_id])
      else
        html << h(match[0])
      end

      cursor = match.end(0)
    end

    html << markdown(report[cursor..])
    TripReportRender.new(html: html, inline_photo_ids: inline_photo_ids)
  end

  def trip_inline_photo_figure(photo, index: nil)
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
          <img src="#{h(image_url(photo, "large"))}" alt="#{h(caption)}" loading="lazy">
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
          <img src="#{h(image_url(photo, "large"))}" alt="#{h(photo.caption)}" loading="lazy">
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

  def heart_button(trip, compact: false)
    heart_count = trip.hearts_dataset.count
    hearted = trip_hearted_by_current_account?(trip)
    label = hearted ? "Remove heart from #{trip.name}" : "Heart #{trip.name}"
    button_class = ["heart-button", ("heart-button-compact" if compact), ("is-hearted" if hearted)].compact.join(" ")
    count_label = "#{format_number(heart_count)} #{(heart_count == 1) ? "heart" : "hearts"}"
    content = heart_icon_svg(filled: hearted) + %(<span class="heart-count">#{h(format_number(heart_count))}</span>)

    if rodauth.logged_in?
      <<~HTML
        <form class="heart-form" action="#{h(trip.public_path)}/hearts" method="post">
          <input type="hidden" name="return_to" value="#{h(return_to_path)}">
          <button class="#{h(button_class)}" type="submit" aria-label="#{h(label)}" aria-pressed="#{hearted ? "true" : "false"}" title="#{h(count_label)}">
            #{content}
          </button>
        </form>
      HTML
    else
      <<~HTML
        <a class="#{h(button_class)}" href="/login" aria-label="#{h("Log in to #{label.downcase}")}" title="#{h(count_label)}">
          #{content}
        </a>
      HTML
    end
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

  def leaflet_tile_url
    "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"
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

  def trip_hearted_by_current_account?(trip)
    rodauth.logged_in? && trip.hearts_dataset.where(account_id: rodauth.session_value.to_i).any?
  end

  def return_to_path
    query = request.query_string.to_s
    query.empty? ? request.path_info : "#{request.path_info}?#{query}"
  end

  def heart_icon_svg(filled:)
    fill = filled ? "currentColor" : "none"

    <<~SVG
      <svg class="heart-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path fill="#{fill}" d="M12 20s-7-4.35-9.33-9.03C1.35 8.33 2.2 5.18 4.93 4.24 7.02 3.52 9.14 4.32 10.5 6.06L12 8l1.5-1.94c1.36-1.74 3.48-2.54 5.57-1.82 2.73.94 3.58 4.09 2.26 6.73C19 15.65 12 20 12 20Z"></path>
      </svg>
    SVG
  end

  def derivative_filename(filename, style)
    return filename if style == "original"

    "#{File.basename(filename, ".*")}.jpg"
  end
end

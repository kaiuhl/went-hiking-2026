# frozen_string_literal: true

require "cgi"
require "json"
require "went_hiking/legacy_urls"
require "went_hiking/markdown"

module ViewHelpers
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

  def format_number(value, precision: nil)
    number = precision ? value.to_f.round(precision) : value
    string = (number.to_f % 1).zero? ? number.to_i.to_s : number.to_s
    integer, decimal = string.split(".", 2)
    integer = integer.reverse.scan(/.{1,3}/).join(",").reverse
    [integer, decimal].compact.join(".")
  end

  def image_url(photo, style = "large")
    variant = photo.variant(style) || photo.variant("original")
    variant&.public_url || "/images/photo-placeholder.svg"
  end

  def avatar_url(account, style = "micro")
    return nil unless account.avatar_file_name

    key = WentHiking::S3Keys.avatar_variant_key(account_id: account.legacy_user_id || account.id, style: style, filename: derivative_filename(account.avatar_file_name, style))
    WentHiking::LegacyUrls.legacy_media_url(key)
  end

  def leaflet_tile_url
    "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"
  end

  private

  def derivative_filename(filename, style)
    return filename if style == "original"

    "#{File.basename(filename, ".*")}.jpg"
  end
end

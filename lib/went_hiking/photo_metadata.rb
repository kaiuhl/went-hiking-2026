# frozen_string_literal: true

require "exifr/jpeg"
require "vips"

module WentHiking
  class PhotoMetadata
    # EXIF orientations 5 through 8 rotate a quarter turn, so the pixels on disk
    # are the transpose of what a browser lays out.
    TRANSPOSED_ORIENTATIONS = (5..8)

    def self.extract(path)
      new(path).extract
    end

    # Width and height as rendered, which is what the markup has to promise.
    def self.dimensions(path)
      new(path).dimensions
    end

    def initialize(path)
      @path = path
    end

    # new_from_file only parses the header, so both reads stay cheap; the
    # pixels on disk are untouched, which is why the EXIF transpose above
    # still applies.
    def dimensions
      image = Vips::Image.new_from_file(@path)
      oriented(image.width, image.height)
    end

    def extract
      image = Vips::Image.new_from_file(@path)
      exif = safe_exif
      width, height = oriented(image.width, image.height, exif: exif)

      {
        width: width,
        height: height,
        taken_at: exif&.date_time_original,
        lat: gps_coordinate(exif&.gps_latitude, exif&.gps_latitude_ref),
        lng: gps_coordinate(exif&.gps_longitude, exif&.gps_longitude_ref),
        camera_model: exif&.model,
        camera_exposure: exif&.exposure_time&.to_s,
        camera_f_stop: positive_float(exif&.f_number),
        camera_iso: Array(exif&.iso_speed_ratings).first
      }.compact
    end

    private

    def oriented(width, height, exif: safe_exif)
      orientation = exif&.orientation.to_i
      TRANSPOSED_ORIENTATIONS.cover?(orientation) ? [height, width] : [width, height]
    rescue
      [width, height]
    end

    def safe_exif
      EXIFR::JPEG.new(@path)
    rescue EXIFR::MalformedJPEG, EXIFR::MalformedImage, Errno::ENOENT
      nil
    end

    def gps_coordinate(value, ref)
      return nil unless value && ref

      decimal = if value.respond_to?(:to_f)
        value.to_f
      else
        parts = Array(value)
        parts[0].to_f + (parts[1].to_f / 60) + (parts[2].to_f / 3600)
      end

      %w[S W].include?(ref.to_s.upcase) ? -decimal : decimal
    end

    def positive_float(value)
      return nil if value.nil?

      number = value.to_f
      number.positive? ? number : nil
    end
  end
end

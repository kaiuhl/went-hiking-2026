# frozen_string_literal: true

require "exifr/jpeg"
require "mini_magick"

module WentHiking
  class PhotoMetadata
    def self.extract(path)
      new(path).extract
    end

    def initialize(path)
      @path = path
    end

    def extract
      image = MiniMagick::Image.open(@path)
      exif = safe_exif

      {
        width: image.width,
        height: image.height,
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

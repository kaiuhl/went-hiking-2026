# frozen_string_literal: true

module WentHiking
  # What an uploaded image actually is, decided by its own bytes rather than by
  # anything the browser claimed about it.
  #
  # Two separate jobs, both of which used to be done on trust:
  #
  #   * the extension a stored object gets, which is what decides the
  #     Content-Type it is later served with, and
  #   * whether the bytes that landed are the image the upload ticket promised.
  #
  # Trusting the client on either one is enough to park an executable SVG on the
  # app's own origin, so neither is trusted now.
  module ImageFormat
    # ISO base media brands that mean "this is a still image", not a movie.
    HEIF_BRANDS = %w[heic heix hevc hevx heim heis hevm hevs mif1 msf1].freeze
    AVIF_BRANDS = %w[avif avis].freeze

    # Every signature below fits in the first 12 bytes; the ISO-BMFF brand at
    # offset 8 is the furthest we ever look.
    SNIFF_BYTES = 16

    EXTENSIONS = {
      jpeg: ".jpg",
      png: ".png",
      gif: ".gif",
      webp: ".webp",
      heic: ".heic",
      avif: ".avif"
    }.freeze

    CONTENT_TYPE_FORMATS = {
      "image/jpeg" => :jpeg,
      "image/jpg" => :jpeg,
      "image/pjpeg" => :jpeg,
      "image/png" => :png,
      "image/x-png" => :png,
      "image/gif" => :gif,
      "image/webp" => :webp,
      "image/heic" => :heic,
      "image/heif" => :heic,
      "image/avif" => :avif
    }.freeze

    module_function

    def format_for_content_type(content_type)
      CONTENT_TYPE_FORMATS[content_type.to_s.split(";").first.to_s.strip.downcase]
    end

    # The extension a stored object should carry, or nil for a type we do not
    # accept at all. Callers treat nil as "refuse", never as "keep what the
    # client sent".
    def extension_for(content_type)
      EXTENSIONS[format_for_content_type(content_type)]
    end

    # The format the leading bytes describe, or nil when the front of the file is
    # not a picture we recognise.
    def sniff(bytes)
      head = bytes.to_s.b
      return :jpeg if head.start_with?("\xFF\xD8\xFF".b)
      return :png if head.start_with?("\x89PNG\r\n\x1A\n".b)
      return :gif if head.start_with?("GIF87a".b, "GIF89a".b)
      return :webp if head.start_with?("RIFF".b) && head.byteslice(8, 4) == "WEBP".b

      if head.byteslice(4, 4) == "ftyp".b
        brand = head.byteslice(8, 4).to_s.downcase
        return :heic if HEIF_BRANDS.include?(brand)
        return :avif if AVIF_BRANDS.include?(brand)
      end

      nil
    end

    def sniff_io(io)
      return nil unless io.respond_to?(:read)

      io.rewind if io.respond_to?(:rewind)
      head = io.read(SNIFF_BYTES)
      io.rewind if io.respond_to?(:rewind)
      sniff(head)
    end

    # Both halves have to resolve and agree. An unrecognised declared type or
    # unrecognisable bytes are a mismatch, not a shrug.
    def matches?(content_type:, bytes:)
      declared = format_for_content_type(content_type)
      !declared.nil? && declared == sniff(bytes)
    end

    def io_matches?(content_type:, io:)
      declared = format_for_content_type(content_type)
      !declared.nil? && declared == sniff_io(io)
    end
  end
end

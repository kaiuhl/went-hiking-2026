# frozen_string_literal: true

require "rack/utils"
require "time"
require "went_hiking/storage"

module MediaRoutes
  # Raster formats only, and deliberately so: this table turns a stored object's
  # extension into the Content-Type it is served with, which makes any
  # script-capable type here (SVG, HTML, XML) a way to run code on our own
  # origin. Anything not listed goes out as application/octet-stream.
  CONTENT_TYPES = {
    ".avif" => "image/avif",
    ".gif" => "image/gif",
    ".heic" => "image/heic",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }.freeze
  MEDIA_CACHE_CONTROL = "public, max-age=86400"
  MEDIA_CHUNK_SIZE = 64 * 1024
  # Belt and braces for objects that predate the checks on the way in: even if
  # something active is already sitting in storage, it loads as a document with
  # no privileges at all. Images fetched as subresources are unaffected.
  MEDIA_CSP = "default-src 'none'; sandbox"

  # Streams a file without slurping it into memory.
  class FileBody
    def initialize(path)
      @path = path
    end

    def each
      File.open(@path, "rb") do |file|
        while (chunk = file.read(MEDIA_CHUNK_SIZE))
          yield chunk
        end
      end
    end
  end

  def route_media(r)
    r.on "system" do
      relative_path = r.remaining_path.to_s.sub(%r{\A/+}, "")
      storage = local_media_storage

      if storage
        serve_local_media(storage, "system/#{Rack::Utils.unescape_path(relative_path)}")
      else
        redirect "#{WentHiking.media_base_url}/system/#{relative_path}", 302
      end
    end
  end

  private

  # Only serve from disk when there is no media host to redirect to and the
  # active storage backend actually holds the bytes locally.
  def local_media_storage
    return nil if WentHiking.media_base_url_configured?

    storage = WentHiking::Storage.current
    storage.local? ? storage : nil
  rescue
    nil
  end

  def serve_local_media(storage, key)
    path = storage.path_for(key)
    not_found unless path && File.file?(path)

    stat = File.stat(path)
    etag = %("#{stat.size.to_s(16)}-#{stat.mtime.to_i.to_s(16)}")
    headers = {
      "Content-Type" => media_content_type(path),
      "Cache-Control" => MEDIA_CACHE_CONTROL,
      "Content-Security-Policy" => MEDIA_CSP,
      "Last-Modified" => stat.mtime.httpdate,
      "ETag" => etag
    }

    if media_not_modified?(etag)
      request.halt [304, headers, []]
    end

    headers["Content-Length"] = stat.size.to_s
    request.halt [200, headers, request.head? ? [] : FileBody.new(path)]
  end

  def media_not_modified?(etag)
    request.get_header("HTTP_IF_NONE_MATCH").to_s.split(",").map(&:strip).include?(etag)
  end

  def media_content_type(path)
    CONTENT_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
  end
end

# frozen_string_literal: true

require "time"

# Headers stamped onto every response on the way out.
#
# An after hook rather than the default_headers plugin because most of the
# interesting responses here never touch the response object at all: static
# files, media, 404s and upload errors each halt with a Rack array of their own,
# and defaults installed on RodaResponse would miss every one of them.
module ResponseHeaders
  SECURITY_HEADERS = {
    # A browser that sniffs its way past a Content-Type undoes the point of
    # having chosen one. This is what keeps a stored file from being promoted to
    # something executable.
    "X-Content-Type-Options" => "nosniff",
    # Other sites get told which site someone came from, not which trip report
    # they were reading.
    "Referrer-Policy" => "strict-origin-when-cross-origin",
    # Nothing here is meant to be framed, and framing is where clickjacking
    # starts.
    "X-Frame-Options" => "DENY"
  }.freeze

  # static_asset_path stamps a file's mtime into its URL, so a request that
  # carries one can be cached forever: a changed file is a changed URL. Assets
  # asked for without one — the fonts site.css names directly, which cannot be
  # templated — get a week plus an ETag to revalidate against.
  VERSIONED_CACHE_CONTROL = "public, max-age=31536000, immutable"
  UNVERSIONED_CACHE_CONTROL = "public, max-age=604800"
  VERSION_QUERY = /(\A|&)v=/

  private

  # Roda's public plugin halts with Rack::Files' own headers, so a caching policy
  # has to be applied on the way out rather than set up front. Calling it here is
  # what marks a response as one of its.
  def serve_static_assets(r)
    @static_asset = true
    r.public
    @static_asset = false
  end

  def apply_response_headers(res)
    return unless res

    headers = res[1]
    return unless headers.respond_to?(:[]=)

    SECURITY_HEADERS.each { |name, value| headers[name] = value }
    apply_static_asset_cache(headers) if @static_asset
  end

  def apply_static_asset_cache(headers)
    headers["Cache-Control"] = versioned_request? ? VERSIONED_CACHE_CONTROL : UNVERSIONED_CACHE_CONTROL
    etag = static_asset_etag(headers)
    headers["ETag"] = etag if etag
  end

  def versioned_request?
    request.query_string.to_s.match?(VERSION_QUERY)
  end

  # Rack::Files sends a modification time and a length but no cache policy and no
  # ETag — and those two headers are exactly what an ETag needs to be made of.
  def static_asset_etag(headers)
    modified = header_value(headers, "Last-Modified")
    length = header_value(headers, "Content-Length")
    return nil unless modified && length

    %("#{length.to_i.to_s(16)}-#{Time.httpdate(modified).to_i.to_s(16)}")
  rescue ArgumentError
    nil
  end

  def header_value(headers, name)
    headers[name] || headers[name.downcase]
  end
end

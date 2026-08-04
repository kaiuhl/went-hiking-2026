# frozen_string_literal: true

module SeoRoutes
  # The pages a crawler should start from; everything else worth indexing is
  # reachable from these and listed individually below.
  SITEMAP_STATIC_PATHS = ["/", "/hikes", "/people", "/about"].freeze

  # Auth, settings, search results, machine endpoints, and tokened flows: pages
  # that are either private, infinite, or meaningless outside a session.
  ROBOTS_DISALLOWED = [
    "/account",
    "/authorize",
    "/change-password",
    "/create-account",
    "/follow/",
    "/hikes/new",
    "/hikes/*/edit",
    "/hikes/*/photos/mobile-upload",
    "/login",
    "/logout",
    "/mcp",
    "/register",
    "/reset-password",
    "/revoke",
    "/search",
    "/token",
    "/unlock-account",
    "/uploads/",
    "/verify-account"
  ].freeze

  def route_seo(r)
    r.get "robots.txt" do
      response["Content-Type"] = "text/plain"
      response["Cache-Control"] = "public, max-age=3600"
      robots_txt
    end

    r.get "sitemap.xml" do
      response["Content-Type"] = "application/xml"
      response["Cache-Control"] = "public, max-age=3600"
      sitemap_xml
    end
  end

  private

  def robots_txt
    lines = ["User-agent: *"]
    lines += ROBOTS_DISALLOWED.map { |path| "Disallow: #{path}" }
    lines << ""
    lines << "Sitemap: #{absolute_url("/sitemap.xml")}"
    lines.join("\n") << "\n"
  end

  # Every published hike and every hiker who published one, plus the handful of
  # front doors. Built as one pass over two column-trimmed queries; at the
  # archive's current size (~8k trips) that is a few hundred kilobytes, well
  # under the 50k-URL sitemap limit.
  def sitemap_xml
    entries = SITEMAP_STATIC_PATHS.map { |path| [absolute_url(path), nil] }

    WentHiking::Models::Trip.published.select(:id, :name, :updated_at).order(:id).each do |trip|
      entries << [absolute_url(trip.public_path), trip.updated_at]
    end

    latest = WentHiking::Models::Trip.published.group(:account_id).select(:account_id).select_append { max(:updated_at).as(:last_trip_at) }
    WentHiking::Models::Account
      .join(latest.from_self.as(:trip_latest), account_id: :id)
      .select(Sequel[:accounts][:id], Sequel[:accounts][:name], Sequel[:accounts][:email], Sequel[:trip_latest][:last_trip_at])
      .order(Sequel[:accounts][:id])
      .each do |account|
        entries << [absolute_url(account.public_path), account[:last_trip_at]]
      end

    xml = +%(<?xml version="1.0" encoding="UTF-8"?>\n)
    xml << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
    entries.each do |url, lastmod|
      xml << "  <url><loc>#{h(url)}</loc>"
      stamp = sitemap_lastmod(lastmod)
      xml << "<lastmod>#{stamp}</lastmod>" if stamp
      xml << "</url>\n"
    end
    xml << "</urlset>\n"
  end

  # Sequel hands back Time on Postgres and (depending on the column) strings on
  # sqlite; either way the sitemap wants a W3C datetime or nothing.
  def sitemap_lastmod(value)
    return nil unless value

    time = value.is_a?(Time) ? value : Time.parse(value.to_s)
    time.utc.iso8601
  rescue ArgumentError, TypeError
    nil
  end
end

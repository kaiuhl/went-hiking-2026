# frozen_string_literal: true

module PlaceRoutes
  # How far a hike can sit from a place and still belong on its page. Peaks
  # and lakes gather trailhead pins from a wide apron; 15 km covers the walk
  # in without pulling in the next valley's hikes.
  PLACE_RADIUS_KM = 15.0

  def route_places(r)
    r.on "places" do
      r.get String do |slug|
        # One namespace for both kinds of page: place slugs carry their
        # dataset prefix, area slugs keep their designators, so they can't
        # collide — and the search strip links either without caring.
        place = WentHiking::Places::Place.active.where(slug: slug).first
        next place_page(place) if place

        area = WentHiking::Places::Area.active.select(*WentHiking::Places::Searcher::AREA_COLUMNS).where(slug: slug).first
        next area_page(area) if area

        not_found
      end
    end
  end

  private

  def place_page(place)
    dataset = trips_near_place(place)
    @place_heading = place.name
    @place_subtitle = place_page_subtitle(place)
    @place_lat = place.latitude
    @place_lng = place.longitude
    @place_attribution = place.source_dataset&.attribution_text
    render_place_page(place.slug, dataset, "near")
  end

  def area_page(area)
    dataset = WentHiking::Models::Trip.published.where(area_id: area[:id])
    @place_heading = area.name
    @place_subtitle = area.area_type.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    @place_lat = area.metadata["center_lat"]
    @place_lng = area.metadata["center_lon"]
    @place_attribution = nil
    render_place_page(area.slug, dataset, "in")
  end

  def render_place_page(slug, dataset, preposition)
    @trips, @pagination = paginated_trip_list(dataset, request.params["page"])
    @map_points = trip_list_scope(dataset)
      .exclude(lat: nil)
      .exclude(lng: nil)
      .limit(100)
      .all
      .map { |trip| {lat: trip.lat, lng: trip.lng, title: trip.name, url: trip.public_path} }
    @place_preposition = preposition
    @pager = {path: "/places/#{slug}", params: {}, label: "#{@place_heading} pages"}
    @title = "Hikes #{preposition} #{@place_heading}"
    view("places/show")
  end

  def trips_near_place(place)
    scope = WentHiking::Models::Trip.published
    return scope.where(place_id: place.id) unless place.latitude && place.longitude

    lat_window = PLACE_RADIUS_KM / 111.0
    lng_window = PLACE_RADIUS_KM / (111.0 * Math.cos(place.latitude * Math::PI / 180.0)).abs
    min_lat = place.latitude - lat_window
    max_lat = place.latitude + lat_window
    min_lng = place.longitude - lng_window
    max_lng = place.longitude + lng_window

    scope.where(
      Sequel.expr(place_id: place.id) |
      (Sequel.expr { lat >= min_lat } & Sequel.expr { lat <= max_lat } &
       Sequel.expr { lng >= min_lng } & Sequel.expr { lng <= max_lng })
    )
  end

  def place_page_subtitle(place)
    parts = [place.place_type.to_s.tr("_", " ").split.map(&:capitalize).join(" ")]
    metadata = place.metadata
    parts << metadata["forest_name"] if metadata["forest_name"]
    parts << WentHiking::Places::States.name_for(place.state_code)
    parts.compact.join(" · ")
  end
end

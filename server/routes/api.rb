# frozen_string_literal: true

module ApiRoutes
  def route_api(r)
    r.on "api" do
      r.get "version" do
        json_payload({app: "went-hiking", env: WentHiking.env})
      end

      r.on "places" do
        r.get "search" do
          response["X-Robots-Tag"] = "noindex"
          query = request.params["q"].to_s.strip
          limit = begin
            Integer(request.params.fetch("limit", 6), 10)
          rescue ArgumentError, TypeError
            6
          end.clamp(1, 20)

          results = (query.length < 2) ? [] : WentHiking::Places::Searcher.new.search(query, limit: limit)
          json_payload({results: results.map { |result| place_search_result(result) }})
        end
      end

      r.post "markdown-preview" do
        route_markdown_preview(r)
      end
    end
  end

  private

  # The searcher speaks in suggestion hashes; the wire speaks in exactly what
  # the typeahead needs, nothing more. Area results (forests, wilderness)
  # carry their precomputed center so picking one can still fly the map.
  def place_search_result(result)
    {
      id: result[:id],
      slug: result[:slug],
      name: result[:name],
      place_type: result[:place_type],
      subtitle: result[:subtitle],
      lat: result[:latitude],
      lng: result[:longitude],
      result_type: result[:result_type]
    }
  end

  def route_markdown_preview(r)
    body = request.POST["body"].to_s
    trip_id = request.POST["trip_id"].to_s

    if trip_id.empty?
      json_payload({html: markdown(body)})
    else
      account = current_account
      trip = account && WentHiking::Models::Trip.where(id: trip_id.to_i, account_id: account.id).first
      not_found unless trip

      photos = trip.photos_dataset.order(:taken_at, :id).all
      rendered = trip_report_render(trip, photos, body: body)
      remaining_photos = photos.reject { |photo| rendered.inline_photo_ids.include?(photo.id) }
      json_payload({html: rendered.html + trip_photo_gallery_html(remaining_photos, all_photos: photos)})
    end
  end
end

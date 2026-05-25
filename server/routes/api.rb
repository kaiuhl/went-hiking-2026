# frozen_string_literal: true

module ApiRoutes
  def route_api(r)
    r.on "api" do
      r.get "version" do
        json_payload({app: "went-hiking", env: WentHiking.env})
      end

      r.post "markdown-preview" do
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
  end
end

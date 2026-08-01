# frozen_string_literal: true

require "went_hiking/pagination"

# One way to build a page of trips for the shared `hikes/trip_list` partial.
# Home, /hikes, /search and the profile year list all render the same markup, so
# they all need the same things loaded, and getting that wrong in one of them is
# how a listing quietly goes back to three queries a row.
module TripListing
  # The partial reads `trip.account`, `trip.photos`, and every photo's variants;
  # eager-loading all three is what turns a page of fifty rows into a fixed
  # handful of queries. The `:id` tiebreaker makes the sort total, without which
  # two trips sharing a timestamp could appear on two pages or on none.
  EAGER = [:account, {photos: :photo_variants}].freeze

  def paginated_trip_list(dataset, page, per_page: WentHiking::Pagination::DEFAULT_PER_PAGE)
    pagination = WentHiking::Pagination.new(page: page, total: dataset.count, per_page: per_page)
    trips = trip_list_scope(dataset)
      .limit(pagination.per_page, pagination.offset)
      .all

    [trips, pagination]
  end

  def trip_list_scope(dataset)
    dataset.eager(*EAGER).reverse_order(:hiked_at, :id)
  end

  # The photos of one trip, for that trip's own pages. Same two problems as a
  # listing, one trip's worth: every photo is asked for two or three variants,
  # and `photo.public_path` walks back up to the trip to build its URL. Threading
  # the parent back in is what the eager loader does for a reciprocal
  # association, done by hand here because these load from a dataset.
  def trip_photos(trip)
    trip.photos_dataset
      .eager(:photo_variants)
      .order(:taken_at, :id)
      .all
      .each { |photo| photo.associations[:trip] = trip }
  end
end

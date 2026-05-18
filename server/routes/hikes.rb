# frozen_string_literal: true

require "date"
require "went_hiking/photo_upload"
require "went_hiking/slug"

module HikeRoutes
  def route_hikes(r)
    r.on "hikes" do
      r.is do
        r.get do
          @trips = WentHiking::Models::Trip.reverse_order(:hiked_at).limit(50).all
          @title = "Recent Hikes"
          view("hikes/index")
        end

        r.post do
          account = authenticated_account
          values, errors, attributes = trip_form_submission(request.POST)
          values[:account_name] = account.name
          setup_trip_form(
            action: "/hikes",
            heading: "New Hike",
            submit_label: "Save hike",
            values: values,
            errors: errors
          )

          if errors.empty?
            trip = WentHiking::Models::Trip.create(attributes.merge(account_id: account.id))
            redirect trip.public_path
          else
            response.status = 422
            view("hikes/form")
          end
        end
      end

      r.get "new" do
        account = authenticated_account
        @title = "New Hike"
        setup_trip_form(
          action: "/hikes",
          heading: "New Hike",
          submit_label: "Save hike",
          values: default_trip_form_values(account)
        )
        view("hikes/form")
      end

      r.get Integer do |legacy_id|
        trip = WentHiking::Models::Trip.where(legacy_trip_id: legacy_id).first || WentHiking::Models::Trip[legacy_id]
        not_found unless trip
        redirect trip.public_path
      end

      r.get String, "photos", Integer do |trip_slug, photo_id|
        @trip = trip_from_slug(trip_slug)
        @photo = @trip.photos_dataset.where(id: photo_id).first || @trip.photos_dataset.where(legacy_photo_id: photo_id).first
        not_found unless @photo
        @title = "#{@trip.name} photo"
        view("photos/show")
      end

      r.get String, "photos", "new" do |trip_slug|
        account = authenticated_account
        @trip = trip_from_slug(trip_slug)
        not_found unless @trip.account_id == account.id

        @title = "Add Photos"
        @photo_errors = []
        view("photos/new")
      end

      r.post String, "photos" do |trip_slug|
        account = authenticated_account
        @trip = trip_from_slug(trip_slug)
        not_found unless @trip.account_id == account.id

        result = WentHiking::PhotoUpload.new(
          account: account,
          trip: @trip,
          upload: request.POST["image"],
          caption: request.POST["caption"]
        ).call

        if result.success?
          redirect @trip.public_path
        else
          @title = "Add Photos"
          @photo_errors = result.errors
          response.status = 422
          view("photos/new")
        end
      end

      r.get String, "photos" do |trip_slug|
        @trip = trip_from_slug(trip_slug)
        @photos = @trip.photos_dataset.order(:taken_at, :id).all
        @title = "Photos from #{@trip.name}"
        view("photos/index")
      end

      r.on String, "comments" do
        retired_feature("comments", title: "New comments are retired.", body: "Legacy comments are preserved on trip pages, but new comments are not part of V2.")
      end

      r.on String, "hearts" do
        retired_feature("hearts", title: "Hearts are retired.", body: "Legacy hearts are preserved as read-only context, but new hearts are not part of V2.")
      end

      r.get String, "edit" do |trip_slug|
        account = authenticated_account
        trip = trip_from_slug(trip_slug)
        not_found unless trip.account_id == account.id

        @title = "Edit #{trip.name}"
        setup_trip_form(
          action: trip.public_path,
          heading: "Edit Hike",
          submit_label: "Save changes",
          values: trip_form_values(trip)
        )
        view("hikes/form")
      end

      r.post String do |trip_slug|
        account = authenticated_account
        trip = trip_from_slug(trip_slug)
        not_found unless trip.account_id == account.id

        values, errors, attributes = trip_form_submission(request.POST)
        values[:account_name] = account.name
        setup_trip_form(
          action: trip.public_path,
          heading: "Edit Hike",
          submit_label: "Save changes",
          values: values,
          errors: errors
        )

        if errors.empty?
          trip.update(attributes)
          redirect trip.public_path
        else
          response.status = 422
          view("hikes/form")
        end
      end

      r.get String do |trip_slug|
        @trip = trip_from_slug(trip_slug)
        @account = @trip.account
        @photos = @trip.photos_dataset.order(:taken_at, :id).all
        @comments = @trip.comments_dataset.order(:created_at, :id).all
        @hearts = @trip.hearts_dataset.all
        @title = @trip.name
        view("hikes/show")
      end
    end

    r.on "users", Integer, "hikes" do |legacy_user_id|
      account = WentHiking::Models::Account.where(legacy_user_id: legacy_user_id).first || WentHiking::Models::Account[legacy_user_id]
      not_found unless account

      r.get Integer do |legacy_trip_id|
        trip = account.trips_dataset.where(legacy_trip_id: legacy_trip_id).first || WentHiking::Models::Trip.where(legacy_trip_id: legacy_trip_id).first
        not_found unless trip
        redirect trip.public_path
      end

      r.get do
        redirect account.public_path
      end
    end

    r.on "with" do
      r.get true do
        redirect "/people/#{r.remaining_path.to_s.sub(%r{\A/+}, "")}"
      end
    end
  end

  private

  def trip_from_slug(value)
    id = WentHiking::Slug.extract_id(value)
    trip = WentHiking::Models::Trip[id] || WentHiking::Models::Trip.where(legacy_trip_id: id).first
    not_found unless trip
    trip
  end

  def authenticated_account
    rodauth.require_authentication
    account = WentHiking::Models::Account[rodauth.session_value]
    not_found unless account
    account
  end

  def setup_trip_form(action:, heading:, submit_label:, values:, errors: [])
    @form_action = action
    @form_heading = heading
    @form_submit_label = submit_label
    @form_values = values
    @form_errors = errors
  end

  def default_trip_form_values(account)
    {
      name: "",
      hiked_at: Date.today.iso8601,
      nights: "0",
      mileage: "",
      elevation: "",
      source_url: "",
      lat: "",
      lng: "",
      report_markdown: "",
      account_name: account.name
    }
  end

  def trip_form_values(trip)
    {
      name: trip.name,
      hiked_at: trip.hiked_at&.to_date&.iso8601,
      nights: trip.nights.to_i.to_s,
      mileage: trip.mileage,
      elevation: trip.elevation,
      source_url: trip.source_url,
      lat: trip.lat,
      lng: trip.lng,
      report_markdown: trip.report_markdown,
      account_name: trip.account.name
    }
  end

  def trip_form_submission(params)
    values = {
      name: params["name"].to_s.strip,
      hiked_at: params["hiked_at"].to_s.strip,
      nights: params["nights"].to_s.strip,
      mileage: params["mileage"].to_s.strip,
      elevation: params["elevation"].to_s.strip,
      source_url: params["source_url"].to_s.strip,
      lat: params["lat"].to_s.strip,
      lng: params["lng"].to_s.strip,
      report_markdown: params["report_markdown"].to_s
    }
    errors = []

    errors << "Name is required." if values[:name].empty?
    hiked_at = parse_hiked_at(values[:hiked_at], errors)

    attributes = {
      name: values[:name],
      hiked_at: hiked_at,
      nights: integer_value(values[:nights], "Nights", errors, min: 0) || 0,
      mileage: decimal_value(values[:mileage], "Mileage", errors, min: 0),
      elevation: integer_value(values[:elevation], "Elevation", errors, min: 0),
      source_url: optional_string(values[:source_url]),
      lat: decimal_value(values[:lat], "Latitude", errors, min: -90, max: 90),
      lng: decimal_value(values[:lng], "Longitude", errors, min: -180, max: 180),
      report_markdown: values[:report_markdown]
    }

    [values, errors.uniq, attributes]
  end

  def parse_hiked_at(value, errors)
    Date.iso8601(value).to_time
  rescue ArgumentError
    errors << "Hike date must be a valid date."
    nil
  end

  def integer_value(value, label, errors, min: nil, max: nil)
    return nil if value.to_s.strip.empty?

    parsed = Integer(value, 10)
    validate_range(parsed, label, errors, min: min, max: max)
    parsed
  rescue ArgumentError
    errors << "#{label} must be a whole number."
    nil
  end

  def decimal_value(value, label, errors, min: nil, max: nil)
    return nil if value.to_s.strip.empty?

    parsed = Float(value)
    validate_range(parsed, label, errors, min: min, max: max)
    parsed
  rescue ArgumentError
    errors << "#{label} must be a number."
    nil
  end

  def validate_range(value, label, errors, min:, max:)
    errors << "#{label} must be at least #{min}." if min && value < min
    errors << "#{label} must be at most #{max}." if max && value > max
  end

  def optional_string(value)
    value.to_s.empty? ? nil : value
  end
end

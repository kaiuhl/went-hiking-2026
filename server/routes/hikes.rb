# frozen_string_literal: true

require "date"
require "went_hiking/direct_photo_upload"
require "went_hiking/hike_flags"
require "went_hiking/hike_notification_scheduler"
require "went_hiking/photo_upload"
require "went_hiking/slug"
require "went_hiking/trip_deletion"
require "went_hiking/upload_tokens"

module HikeRoutes
  DRAFT_NAME = "Untitled Hike"
  DRAFT_SLUG = "untitled-hike"
  STALE_DRAFT_AGE = 7 * 24 * 60 * 60

  def route_hikes(r)
    r.on "hikes" do
      r.is do
        r.get do
          @trips, @pagination = paginated_trip_list(WentHiking::Models::Trip.published, request.params["page"])
          @pager = {path: "/hikes", params: {}, label: "Hike archive pages"}
          @title = "Recent Hikes"
          @description = "Browse #{@pagination.total} hiking and backpacking trip reports — routes, mileage, photos, and stories from the trail since 2010."
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
            trip = WentHiking::Models::Trip.create(attributes.merge(account_id: account.id, status: "published", published_at: Time.now))
            update_photo_captions(trip, request.POST["photo_captions"])
            WentHiking::HikeNotificationScheduler.schedule_trip(trip)
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

      r.post "drafts" do
        account = authenticated_account
        trip = reusable_draft(account) || create_draft(account)
        sweep_stale_drafts(account, keep_id: trip.id)

        json_payload(
          {
            trip_id: trip.id,
            edit_url: "#{trip.public_path}/edit",
            save_url: trip.public_path,
            upload_url: "#{trip.public_path}/photos/direct-upload"
          },
          status: 201
        )
      end

      r.get Integer do |legacy_id|
        trip = WentHiking::Models::Trip.published.where(legacy_trip_id: legacy_id).first || WentHiking::Models::Trip.published.where(id: legacy_id).first
        not_found unless trip
        redirect trip.public_path, 301
      end

      r.get String, "photos", Integer do |trip_slug, photo_id|
        @trip = trip_from_slug(trip_slug)
        @photo = @trip.photos_dataset.where(id: photo_id).first || @trip.photos_dataset.where(legacy_photo_id: photo_id).first
        not_found unless @photo
        redirect_unless_canonical(@photo.public_path)
        @title = "#{@trip.name} photo"
        view("photos/show")
      end

      # Photos are part of composing a hike now, so the standalone upload page
      # hands off to the editor. The multipart POST below stays put as the
      # no-JavaScript path.
      r.get String, "photos", "new" do |trip_slug|
        account = authenticated_account
        trip = owned_trip_from_slug(trip_slug, account)
        redirect "#{trip.public_path}/edit"
      end

      # Phone-friendly upload page reached via a signed link from the MCP
      # connector -- no logged-in session required, just a valid token.
      r.get String, "photos", "mobile-upload" do |trip_slug|
        @trip = trip_from_slug(trip_slug, include_drafts: true)
        @upload_token = request.params["token"].to_s
        token_trip = WentHiking::UploadTokens.trip_from(@upload_token)
        not_found unless token_trip && token_trip.id == @trip.id

        @photos = trip_photos(@trip)
        @title = "Add photos to #{@trip.name}"
        @noindex = true
        view("photos/mobile_upload")
      end

      r.post String, "photos", "direct-upload" do |trip_slug|
        account, @trip = trip_upload_authorization(trip_slug)

        result = WentHiking::DirectPhotoUpload.new(
          account: account,
          trip: @trip,
          filename: request.POST["filename"],
          content_type: request.POST["content_type"],
          file_size: request.POST["file_size"],
          caption: request.POST["caption"]
        ).call

        if result.success?
          json_payload(
            photo_editor_item(result.photo).merge(
              photo_id: result.photo.id,
              upload: result.upload,
              finalize_url: "#{@trip.public_path}/photos/#{result.photo.id}/finalize",
              redirect_url: @trip.public_path
            ),
            status: 201
          )
        else
          json_payload({errors: result.errors}, status: 422)
        end
      end

      r.post String, "photos", Integer, "caption" do |trip_slug, photo_id|
        account, @trip = trip_upload_authorization(trip_slug)
        photo = @trip.photos_dataset.where(id: photo_id, account_id: account.id).first
        not_found unless photo

        photo.update(caption: optional_string(request.POST["caption"].to_s.strip), updated_at: Time.now)
        json_payload(photo_editor_item(photo))
      end

      r.post String, "photos", Integer, "delete" do |trip_slug, photo_id|
        account = authenticated_account
        @trip = owned_trip_from_slug(trip_slug, account)
        photo = @trip.photos_dataset.where(id: photo_id, account_id: account.id).first
        not_found unless photo

        WentHiking::TripDeletion.delete_photo_files(photo)
        WentHiking.db.transaction do
          photo.photo_variants_dataset.delete
          photo.destroy
        end

        json_payload({deleted_photo_id: photo_id})
      end

      r.post String, "photos", Integer, "finalize" do |trip_slug, photo_id|
        account, @trip = trip_upload_authorization(trip_slug)

        result = WentHiking::DirectPhotoUpload.finalize(account: account, trip: @trip, photo_id: photo_id)

        if result.success?
          json_payload(photo_editor_item(result.photo).merge(redirect_url: @trip.public_path))
        else
          json_payload({errors: result.errors}, status: 422)
        end
      end

      r.post String, "photos" do |trip_slug|
        account, @trip = trip_upload_authorization(trip_slug)

        result = WentHiking::PhotoUpload.new(
          account: account,
          trip: @trip,
          upload: request.POST["image"],
          caption: request.POST["caption"]
        ).call

        if result.success?
          upload_token = request.params["upload_token"].to_s
          redirect(upload_token.empty? ? @trip.public_path : "#{@trip.public_path}/photos/mobile-upload?token=#{upload_token}")
        else
          @title = "Add Trail Photos"
          @photo_errors = result.errors
          @photo_caption = request.POST["caption"].to_s
          response.status = 422
          view("photos/new")
        end
      end

      r.get String, "photos" do |trip_slug|
        @trip = trip_from_slug(trip_slug)
        redirect_unless_canonical("#{@trip.public_path}/photos")
        @photos = trip_photos(@trip)
        @title = "Photos from #{@trip.name}"
        @description = "#{@photos.size} #{(@photos.size == 1) ? "photo" : "photos"} from #{@trip.name}, hiked by #{@trip.account.name} on Went Hiking."
        view("photos/index")
      end

      r.on String, "comments" do
        retired_feature("comments", title: "New comments are taking a trail nap.", body: "The original conversations still show up on trip pages. Fresh commenting can come back once the new site has its boots under it.")
      end

      r.on String, "hearts" do |trip_slug|
        trip = trip_from_slug(trip_slug)

        r.post do
          account = authenticated_account
          heart = trip.hearts_dataset.where(account_id: account.id).first

          if heart
            heart.destroy
          else
            WentHiking::Models::Heart.create(account_id: account.id, trip_id: trip.id, legacy_read_only: false)
          end

          redirect heart_return_path(request.POST["return_to"], trip)
        end

        r.get do
          redirect trip.public_path
        end
      end

      r.get String, "edit" do |trip_slug|
        account = authenticated_account
        trip = owned_trip_from_slug(trip_slug, account)

        @title = "Edit #{trip.name}"
        setup_trip_form(
          action: trip.public_path,
          heading: "Edit Hike",
          submit_label: "Save changes",
          values: trip_form_values(trip),
          trip: trip
        )
        view("hikes/form")
      end

      # Drafts save themselves as they are written. Publishing is still the
      # explicit POST below: autosave never flips status, never regenerates the
      # slug, and refuses to touch a hike that is already live.
      r.post String, "autosave" do |trip_slug|
        account = authenticated_account
        trip = owned_trip_from_slug(trip_slug, account)

        if trip.draft?
          attributes, errors = autosave_attributes(request.POST)
          trip.update(attributes.merge(updated_at: Time.now)) unless attributes.empty?
          payload = {saved_at: Time.now.iso8601, trip_id: trip.id}

          if errors.empty?
            json_payload(payload)
          else
            json_payload(payload.merge(errors: errors), status: 422)
          end
        else
          json_payload({errors: {base: "Published hikes save with the Save changes button."}}, status: 422)
        end
      end

      r.post String, "delete" do |trip_slug|
        account = authenticated_account
        trip = owned_trip_from_slug(trip_slug, account)

        WentHiking::TripDeletion.call(trip)
        redirect account.public_path
      end

      r.post String do |trip_slug|
        account = authenticated_account
        trip = owned_trip_from_slug(trip_slug, account)

        values, errors, attributes = trip_form_submission(request.POST)
        values[:account_name] = account.name
        setup_trip_form(
          action: trip.public_path,
          heading: "Edit Hike",
          submit_label: "Save changes",
          values: values,
          errors: errors,
          trip: trip
        )

        if errors.empty?
          was_draft = trip.draft?
          update_attributes = attributes
          if was_draft
            update_attributes = update_attributes.merge(
              slug: WentHiking::Slug.generate(attributes[:name]),
              status: "published",
              published_at: Time.now
            )
          end
          trip.update(update_attributes)
          update_photo_captions(trip, request.POST["photo_captions"])
          WentHiking::HikeNotificationScheduler.schedule_trip(trip) if was_draft
          redirect trip.public_path
        else
          response.status = 422
          view("hikes/form")
        end
      end

      r.get String do |trip_slug|
        @trip = trip_from_slug(trip_slug)
        redirect_unless_canonical(@trip.public_path)
        @account = @trip.account
        @photos = trip_photos(@trip)
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
        trip = account.trips_dataset.published.where(legacy_trip_id: legacy_trip_id).first || WentHiking::Models::Trip.published.where(legacy_trip_id: legacy_trip_id).first
        not_found unless trip
        redirect trip.public_path, 301
      end

      r.get do
        redirect account.public_path, 301
      end
    end

    r.on "with" do
      r.get true do
        redirect "/people/#{r.remaining_path.to_s.sub(%r{\A/+}, "")}", 301
      end
    end
  end

  private

  # Every spelling of a slug with the right ID prefix resolves — including the
  # legacy-ID spelling and any stale slug from before a rename — so the wrong
  # spellings permanently redirect rather than serving a duplicate of the page.
  def redirect_unless_canonical(canonical_path)
    return if request.path == canonical_path

    query = request.query_string.to_s
    redirect(query.empty? ? canonical_path : "#{canonical_path}?#{query}", 301)
  end

  def create_draft(account)
    now = Time.now
    WentHiking::Models::Trip.create(
      account_id: account.id,
      name: DRAFT_NAME,
      slug: DRAFT_SLUG,
      hiked_at: Date.today.to_time,
      nights: 0,
      report_markdown: "",
      status: "draft",
      published_at: nil,
      created_at: now,
      updated_at: now
    )
  end

  # One untouched scratch draft per account: the editor asks for a draft on every
  # visit, and without this each visit stranded another invisible trip row.
  def reusable_draft(account)
    account.trips_dataset
      .drafts
      .where(name: DRAFT_NAME)
      .reverse_order(:created_at, :id)
      .all
      .find { |trip| empty_draft?(trip) }
  end

  def sweep_stale_drafts(account, keep_id: nil)
    cutoff = Time.now - STALE_DRAFT_AGE

    account.trips_dataset
      .drafts
      .where(name: DRAFT_NAME)
      .where { created_at < cutoff }
      .all
      .each do |trip|
        next if trip.id == keep_id
        next unless empty_draft?(trip)

        WentHiking::TripDeletion.call(trip)
      end
  end

  def empty_draft?(trip)
    trip.report_markdown.to_s.strip.empty? && trip.photos_dataset.empty?
  end

  def trip_from_slug(value, include_drafts: false)
    id = WentHiking::Slug.extract_id(value)
    trip = WentHiking::Models::Trip[id] || WentHiking::Models::Trip.where(legacy_trip_id: id).first
    not_found unless trip
    not_found if trip.draft? && !include_drafts
    trip
  end

  def owned_trip_from_slug(value, account)
    trip = trip_from_slug(value, include_drafts: true)
    not_found unless trip.account_id == account.id
    trip
  end

  # Photo upload endpoints accept either the owner's logged-in session or a
  # signed upload token minted for the trip (the MCP mobile upload flow).
  def trip_upload_authorization(trip_slug)
    trip = trip_from_slug(trip_slug, include_drafts: true)
    token = request.params["upload_token"].to_s

    unless token.empty?
      token_trip = WentHiking::UploadTokens.trip_from(token)
      return [trip.account, trip] if token_trip && token_trip.id == trip.id
    end

    account = authenticated_account
    not_found unless trip.account_id == account.id
    [account, trip]
  end

  def authenticated_account
    rodauth.require_authentication
    account = WentHiking::Models::Account[rodauth.session_value]
    not_found unless account
    account
  end

  # A path back to where the heart was clicked, and nowhere else. "//evil.com"
  # and "/\evil.com" are both protocol-relative URLs once a browser gets hold of
  # them, so the second character has to be checked as well as the first.
  def heart_return_path(value, trip)
    path = value.to_s
    return path if path.start_with?("/") && !path.match?(%r{\A/[\\/]}) && !path.match?(/[\r\n]/)

    trip.public_path
  end

  def setup_trip_form(action:, heading:, submit_label:, values:, errors: [], trip: nil)
    @form_action = action
    @form_heading = heading
    @form_submit_label = submit_label
    @form_values = values
    @form_errors = errors
    @form_trip = trip
    @form_photos = trip ? trip_photos(trip) : []
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
    }.merge(WentHiking::HikeFlags.keys.to_h { |key| [key, ""] })
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
    }.merge(WentHiking::HikeFlags.keys.to_h { |key| [key, trip[key].to_s] })
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
    WentHiking::HikeFlags.keys.each { |key| values[key] = params[key.to_s].to_s.strip }
    errors = []

    errors << "Name is required." if values[:name].empty?
    hiked_at = parse_hiked_at(values[:hiked_at], errors)
    validate_coordinate_pair(values, errors)

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
    WentHiking::HikeFlags.keys.each { |key| attributes[key] = flag_value(key, values[key], errors) }

    [values, errors.uniq, attributes]
  end

  # The flag chips are click-to-choose, so an unknown token only ever arrives
  # by tampering; it is refused rather than laundered into the vocabulary.
  def flag_value(key, value, errors)
    return nil if value.empty?
    return value if WentHiking::HikeFlags.valid?(key, value)

    errors << "#{WentHiking::HikeFlags.label(key)} isn't one of the offered choices."
    nil
  end

  # Autosave is deliberately more forgiving than publishing: a half-typed number
  # should not cost the writer the sentence they are in the middle of. Fields
  # that parse are written, fields that do not come back as per-field errors the
  # editor pins to the offending chip, and anything absent is left alone.
  def autosave_attributes(params)
    attributes = {}
    errors = {}

    if params.key?("name")
      name = params["name"].to_s.strip
      attributes[:name] = name.empty? ? DRAFT_NAME : name
    end

    if params.key?("hiked_at")
      value = params["hiked_at"].to_s.strip
      begin
        attributes[:hiked_at] = Date.iso8601(value).to_time
      rescue ArgumentError
        errors[:hiked_at] = "Hike date must be a valid date." unless value.empty?
      end
    end

    autosave_number(params, "nights", :nights, errors, integer: true, min: 0, blank: 0, label: "Nights") { |value| attributes[:nights] = value }
    autosave_number(params, "mileage", :mileage, errors, min: 0, label: "Mileage") { |value| attributes[:mileage] = value }
    autosave_number(params, "elevation", :elevation, errors, integer: true, min: 0, label: "Elevation") { |value| attributes[:elevation] = value }

    attributes[:source_url] = optional_string(params["source_url"].to_s.strip) if params.key?("source_url")
    attributes[:report_markdown] = params["report_markdown"].to_s if params.key?("report_markdown")

    WentHiking::HikeFlags.keys.each do |key|
      next unless params.key?(key.to_s)

      flag_errors = []
      value = flag_value(key, params[key.to_s].to_s.strip, flag_errors)
      if flag_errors.empty?
        attributes[key] = value
      else
        errors[key] = flag_errors.first
      end
    end

    autosave_coordinates(params, attributes, errors)

    [attributes, errors]
  end

  def autosave_number(params, key, error_key, errors, integer: false, min: nil, max: nil, blank: nil, label: nil)
    return unless params.key?(key)

    value = params[key].to_s.strip
    return yield(blank) if value.empty?

    parsed_errors = []
    parsed = if integer
      integer_value(value, label || key, parsed_errors, min: min, max: max)
    else
      decimal_value(value, label || key, parsed_errors, min: min, max: max)
    end

    if parsed_errors.empty?
      yield(parsed)
    else
      errors[error_key] = parsed_errors.first
    end
  end

  # Latitude and longitude move as a pair, so autosave rejects a half-set
  # location the same way publishing does rather than storing a stray number.
  def autosave_coordinates(params, attributes, errors)
    return unless params.key?("lat") || params.key?("lng")

    lat = params["lat"].to_s.strip
    lng = params["lng"].to_s.strip

    if lat.empty? && lng.empty?
      attributes[:lat] = nil
      attributes[:lng] = nil
      return
    end

    pair_errors = []
    parsed_lat = decimal_value(lat, "Latitude", pair_errors, min: -90, max: 90)
    parsed_lng = decimal_value(lng, "Longitude", pair_errors, min: -180, max: 180)

    if parsed_lat && parsed_lng && pair_errors.empty?
      attributes[:lat] = parsed_lat
      attributes[:lng] = parsed_lng
    else
      errors[:location] = pair_errors.first || "Drop a map pin with both latitude and longitude, or clear the location."
    end
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
    unless parsed.finite?
      errors << "#{label} must be a number."
      return nil
    end
    validate_range(parsed, label, errors, min: min, max: max)
    parsed
  rescue ArgumentError
    errors << "#{label} must be a number."
    nil
  end

  def validate_coordinate_pair(values, errors)
    has_lat = !values[:lat].to_s.empty?
    has_lng = !values[:lng].to_s.empty?
    return if has_lat == has_lng

    errors << "Drop a map pin with both latitude and longitude, or clear the location."
  end

  def validate_range(value, label, errors, min:, max:)
    errors << "#{label} must be at least #{min}." if min && value < min
    errors << "#{label} must be at most #{max}." if max && value > max
  end

  def optional_string(value)
    value.to_s.empty? ? nil : value
  end

  def update_photo_captions(trip, captions)
    return unless captions.respond_to?(:each)

    captions.each do |photo_id, caption|
      photo = trip.photos_dataset.where(id: photo_id.to_i).first
      next unless photo

      photo.update(caption: optional_string(caption.to_s.strip), updated_at: Time.now)
    end
  end
end

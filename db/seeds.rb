# frozen_string_literal: true

require_relative "../config/boot"
require "bcrypt"
require "date"
require "went_hiking/models"

module WentHiking
  module Seeds
    LIVE_BASE_URL = "http://wenthiking.com"

    ACCOUNT = {
      legacy_user_id: 51,
      email: "jen@example.wenthiking.local",
      name: "Jen",
      location: "Pacific Northwest",
      avatar_file_name: "#{LIVE_BASE_URL}/system/avatars/51/medium/P9140528.jpg",
      avatar_content_type: "image/jpeg"
    }.freeze

    LOCAL_ACCOUNT = {
      email: "kaiuhl@gmail.com",
      name: "Kyle Meyer",
      location: "Portland, Oregon",
      password: "password"
    }.freeze

    TRIPS = [
      {
        legacy_trip_id: 8223,
        name: "Coyote Wall",
        hiked_at: "2026-04-25",
        mileage: 7.5,
        elevation: 1750,
        nights: 0,
        lat: 45.7132,
        lng: -121.399,
        report_markdown: "Last Alpenhounds hike, bittersweet. ...",
        photos: [[43384, "Alpenhounds_on_Coyote_Wall.jpg"]]
      },
      {
        legacy_trip_id: 8222,
        name: "Angel's rest",
        hiked_at: "2026-04-30",
        mileage: 4.5,
        elevation: 1250,
        nights: 0,
        lat: 45.5631,
        lng: -122.154,
        report_markdown: "Lucky Day- my son agreed to go on a hike with me! ...",
        photos: [[43383, "me_and_Ev.jpg"]]
      },
      {
        legacy_trip_id: 8221,
        name: "Sedona",
        hiked_at: "2026-04-01",
        mileage: 22.0,
        elevation: 4500,
        nights: 0,
        lat: 34.8286,
        lng: -111.804,
        report_markdown: "Trip to the Arizona desert. Day 1- visited Perry Mesa in the Agua Fria National Monument. This plateau has pueblo ruins, petroglyphs, and big red-rock views.",
        photos: [
          [43363, "Agua_Fria_potsherds.jpg"],
          [43361, "Pueblo_la_plata_petroglyph.jpg"],
          [43362, "baby_canyon_petro.jpg"],
          [43364, "agua_fria_metate.jpg"],
          [43365, "agua_fria_mallow.jpg"],
          [43366, "Sedona_cathedral_rocks.jpg"],
          [43354, "Morning_Glory_approach.jpg"],
          [43357, "Morning_Glory_Spire_View_E_from_p1.jpg"],
          [43355, "Morning_Glory_Spire-_Jen_and_Melinda.jpg"],
          [43356, "Morning_Glory_Spire_CFM_on_top.jpg"],
          [43360, "Loy_Ruins_3.jpg"],
          [43359, "Loy_Ruins_2.jpg"],
          [43358, "Loy_ledges.jpg"],
          [43351, "Courthouse_Butte_view_of_Bell_Rock.jpg"],
          [43352, "Courthouse_Butte_CFM_on_top.jpg"],
          [43353, "Courthouse_Butte_Layers.jpg"]
        ]
      },
      {
        legacy_trip_id: 8220,
        name: "Devils/Wahkeena",
        hiked_at: "2026-03-28",
        mileage: 9.0,
        elevation: 2500,
        nights: 0,
        lat: 45.5628,
        lng: -122.119,
        report_markdown: "Alpenhounds hike.",
        photos: []
      },
      {
        legacy_trip_id: 8219,
        name: "Lower Greenleaf",
        hiked_at: "2026-03-27",
        mileage: 5.0,
        elevation: 750,
        nights: 0,
        lat: 45.6662,
        lng: -121.957,
        report_markdown: "Explored some of the new trails being built in the area. Lower Greenleaf Falls has had some big washouts since the last visit.",
        photos: []
      },
      {
        legacy_trip_id: 8217,
        name: "Broughton",
        hiked_at: "2026-03-19",
        mileage: 4.0,
        elevation: 500,
        nights: 0,
        lat: 45.5399,
        lng: -122.372,
        report_markdown: "Goofing around at Broughton Bluff. Walked the Phone Home Boulders trail and examined some of the crags.",
        photos: []
      },
      {
        legacy_trip_id: 8216,
        name: "The Pinnacles",
        hiked_at: "2026-02-28",
        mileage: 5.0,
        elevation: 750,
        nights: 0,
        lat: 45.6686,
        lng: -121.849,
        report_markdown: "Alpenhounds.",
        photos: []
      },
      {
        legacy_trip_id: 8215,
        name: "Hardy Ridge",
        hiked_at: "2026-03-14",
        mileage: 9.5,
        elevation: 2250,
        nights: 0,
        lat: 45.6614,
        lng: -122.028,
        report_markdown: "Alpenhounds!",
        photos: [
          [43373, "Hardy_Ridge_running_belay.jpg"],
          [43372, "Hardy_Ridge_Alpenhounds.jpg"]
        ]
      },
      {
        legacy_trip_id: 8214,
        name: "Mack's Canyon",
        hiked_at: "2026-03-20",
        mileage: 12.5,
        elevation: 1750,
        nights: 1,
        lat: 45.4726,
        lng: -120.836,
        report_markdown: "This was supposed to be a ski trip to the Tilly Jane Cabin. Thin cover and rain pushed us toward the Deschutes instead.",
        photos: [
          [43370, "Macks3.jpg"],
          [43367, "Macks_team.jpg"],
          [43369, "Macks_2.jpg"],
          [43371, "above_Macks.jpg"]
        ]
      },
      {
        legacy_trip_id: 8213,
        name: "Multnomah Wahkeena Loop",
        hiked_at: "2026-01-23",
        mileage: 5.0,
        elevation: 1500,
        nights: 0,
        lat: 45.5763,
        lng: -122.121,
        report_markdown: "Chilly with a few icy spots.",
        photos: []
      },
      {
        legacy_trip_id: 8212,
        name: "MSH",
        hiked_at: "2026-01-15",
        mileage: 8.0,
        elevation: 3000,
        nights: 0,
        lat: 46.1792,
        lng: -122.178,
        report_markdown: "Beautiful sunny day. Lower mountain snow did not refreeze overnight, and the bootpack was total mashed potatoes.",
        photos: [
          [43348, "MSH_Jan_2026.jpg"],
          [43349, "Adams_from_MSH.jpg"]
        ]
      },
      {
        legacy_trip_id: 8211,
        name: "Cedar Falls",
        hiked_at: "2026-01-08",
        mileage: 6.0,
        elevation: 1250,
        nights: 0,
        lat: 45.6607,
        lng: -121.979,
        report_markdown: "A rainy short hike from Bonneville Hot Springs to the Cedar Falls overlook.",
        photos: [
          [43350, "Bonneville_HS.jpg"],
          [43347, "Cedar_Creek_crossing.jpg"]
        ]
      },
      {
        legacy_trip_id: 8210,
        name: "Dog Mountain",
        hiked_at: "2025-05-17",
        mileage: 6.9,
        elevation: 2850,
        nights: 0,
        lat: 45.6998,
        lng: -121.7072,
        report_markdown: "A bright spring hike with wildflowers along the ridge.",
        photos: []
      }
    ].freeze

    module_function

    def run
      account = seed_account
      seeded_photos = 0

      TRIPS.each do |trip_data|
        seeded_photos += seed_trip(account, trip_data)
      end

      seed_local_account

      puts "Seeded #{TRIPS.size} trips, #{seeded_photos} live photo references, and local login #{LOCAL_ACCOUNT[:email]}."
    end

    def seed_account
      now = Time.now
      created_at = Time.local(2010, 7, 1, 12)
      values = ACCOUNT.merge(
        slug: Slug.generate(ACCOUNT[:name]),
        status_id: 2,
        created_at: created_at,
        updated_at: now
      )

      account = Models::Account.where(legacy_user_id: ACCOUNT[:legacy_user_id]).first || Models::Account.where(email: ACCOUNT[:email]).first
      return Models::Account.create(values) unless account

      account.set(values.except(:created_at))
      account.save_changes
      account
    end

    def seed_local_account
      now = Time.now
      values = {
        email: LOCAL_ACCOUNT.fetch(:email),
        name: LOCAL_ACCOUNT.fetch(:name),
        slug: Slug.generate(LOCAL_ACCOUNT.fetch(:name)),
        location: LOCAL_ACCOUNT.fetch(:location),
        status_id: 2,
        verified_at: now,
        created_at: now,
        updated_at: now
      }

      account = Models::Account.where(email: LOCAL_ACCOUNT.fetch(:email)).first
      account = account ? update_model(account, values) : Models::Account.create(values)
      password_hash = BCrypt::Password.create(LOCAL_ACCOUNT.fetch(:password)).to_s
      password_dataset = WentHiking.db[:account_password_hashes].where(id: account.id)

      if password_dataset.count.positive?
        password_dataset.update(password_hash: password_hash)
      else
        WentHiking.db[:account_password_hashes].insert(id: account.id, password_hash: password_hash)
      end

      account
    end

    def seed_trip(account, trip_data)
      now = Time.now
      hiked_at = time_from_date(trip_data.fetch(:hiked_at))
      trip_values = trip_data.except(:photos).merge(
        account_id: account.id,
        slug: Slug.generate(trip_data.fetch(:name)),
        source_url: live_trip_url(account, trip_data),
        hiked_at: hiked_at,
        created_at: hiked_at,
        updated_at: now
      )

      trip = Models::Trip.where(legacy_trip_id: trip_data.fetch(:legacy_trip_id)).first
      trip = trip ? update_model(trip, trip_values) : Models::Trip.create(trip_values)

      trip_data.fetch(:photos).each do |legacy_photo_id, filename|
        seed_photo(account, trip, legacy_photo_id, filename, hiked_at)
      end

      trip_data.fetch(:photos).size
    end

    def seed_photo(account, trip, legacy_photo_id, filename, taken_at)
      now = Time.now
      photo_values = {
        account_id: account.id,
        trip_id: trip.id,
        legacy_photo_id: legacy_photo_id,
        legacy_image_file_name: filename,
        content_type: "image/jpeg",
        taken_at: taken_at,
        caption: trip.name,
        created_at: taken_at,
        updated_at: now
      }

      photo = Models::Photo.where(legacy_photo_id: legacy_photo_id).first
      photo = photo ? update_model(photo, photo_values) : Models::Photo.create(photo_values)
      seed_photo_variant(photo, legacy_photo_id, filename)
    end

    def seed_photo_variant(photo, legacy_photo_id, filename)
      now = Time.now
      variant_values = {
        photo_id: photo.id,
        style: "large",
        filename: filename,
        legacy_path: "#{LIVE_BASE_URL}/system/images/#{legacy_photo_id}/large/#{filename}",
        created_at: photo.created_at,
        updated_at: now
      }

      variant = photo.photo_variants_dataset.where(style: "large").first
      variant ? update_model(variant, variant_values) : Models::PhotoVariant.create(variant_values)
    end

    def update_model(model, values)
      model.set(values.except(:created_at))
      model.save_changes
      model
    end

    def live_trip_url(account, trip_data)
      account_slug = Slug.generate(account.name)
      trip_slug = Slug.generate(trip_data.fetch(:name))
      "#{LIVE_BASE_URL}/users/#{account.legacy_user_id}-#{account_slug}/hikes/#{trip_data.fetch(:legacy_trip_id)}-#{trip_slug}"
    end

    def time_from_date(value)
      date = Date.iso8601(value)
      Time.local(date.year, date.month, date.day, 12)
    end
  end
end

WentHiking::Seeds.run if __FILE__ == $PROGRAM_NAME

# frozen_string_literal: true

require "date"
require "json"
require "mcp"
require "went_hiking/hike_flags"
require "went_hiking/hike_notification_scheduler"
require "went_hiking/models"
require "went_hiking/slug"
require "went_hiking/upload_tokens"

module WentHiking
  module Mcp
    module Tools
      class ToolError < StandardError; end

      class Base < MCP::Tool
        class << self
          def call(server_context:, **args)
            payload = handle(account: server_context[:account], scopes: Array(server_context[:scopes]), args: args)
            MCP::Tool::Response.new([{type: "text", text: JSON.pretty_generate(payload)}])
          rescue ToolError => error
            MCP::Tool::Response.new([{type: "text", text: error.message}], error: true)
          end

          private

          def require_write!(scopes)
            return if scopes.include?(WRITE_SCOPE)

            raise ToolError, "This connection was authorized without the #{WRITE_SCOPE} scope, so it can only read hikes. Reconnect and allow write access to make changes."
          end

          def owned_trip!(account, trip_id)
            trip = account.trips_dataset.where(id: trip_id.to_i).first
            raise ToolError, "No hike with id #{trip_id} belongs to #{account.name}. Use list_my_hikes to see available hikes." unless trip

            trip
          end

          def parse_hiked_at!(value)
            Date.iso8601(value.to_s).to_time
          rescue ArgumentError
            raise ToolError, "hiked_at must be an ISO 8601 date such as 2026-07-18."
          end

          def public_url(path)
            "#{WentHiking.public_base_url.to_s.sub(%r{/+\z}, "")}#{path}"
          end

          def trip_summary(trip)
            {
              trip_id: trip.id,
              name: trip.name,
              status: trip.status,
              hiked_at: trip.hiked_at&.to_date&.iso8601,
              nights: trip.nights,
              mileage: trip.mileage,
              elevation: trip.elevation,
              photo_count: trip.photos_dataset.count,
              url: trip.published? ? public_url(trip.public_path) : nil,
              edit_url: public_url("#{trip.public_path}/edit")
            }.compact
          end

          def trip_details(trip)
            trip_summary(trip).merge(
              source_url: trip.source_url,
              lat: trip.lat,
              lng: trip.lng,
              published_at: trip.published_at&.iso8601,
              report_markdown: trip.report_markdown.to_s,
              photos: trip.photos_dataset.order(:taken_at, :id).all.map { |photo| photo_details(photo) }
            ).merge(condition_flags(trip)).compact
          end

          def condition_flags(trip)
            HikeFlags.keys.each_with_object({}) { |key, memo| memo[key] = trip[key] }
          end

          # The optional condition-flag properties, shared by create and
          # update so the schemas cannot drift from the HikeFlags vocabulary.
          # The empty string is in the enum because the MCP layer validates
          # arguments against it, and "" is how a set flag is cleared.
          def flag_properties
            HikeFlags.all.each_with_object({}) do |flag, properties|
              properties[flag.key] = {
                type: "string",
                enum: flag.tokens + [""],
                description: "Optional flag: #{flag.label.downcase} observed on the hike. Set it only when the member said so; an empty string clears it."
              }
            end
          end

          def apply_flag_args!(args, target)
            HikeFlags.all.each do |flag|
              next unless args.key?(flag.key)

              value = args[flag.key].to_s.strip
              if value.empty?
                target[flag.key] = nil
              elsif HikeFlags.valid?(flag.key, value)
                target[flag.key] = value
              else
                raise ToolError, "#{flag.key} must be one of: #{flag.tokens.join(", ")}. Pass an empty string to clear it."
              end
            end
          end

          def photo_details(photo)
            {
              photo_id: photo.id,
              handle: "{{ photo:#{photo.id} }}",
              caption: photo.caption,
              taken_at: photo.taken_at&.iso8601,
              lat: photo.lat,
              lng: photo.lng,
              camera_model: photo.camera_model,
              page_url: public_url(photo.public_path)
            }.compact
          end
        end
      end

      class ListMyHikes < Base
        tool_name "list_my_hikes"
        description "List the member's hikes on Went Hiking, most recent first. Includes private drafts. Use this to find a hike's trip_id, check whether a trip was already posted, or pull up past reports."
        input_schema(
          properties: {
            status: {type: "string", enum: %w[all draft published], description: "Filter by publication status. Defaults to all."},
            limit: {type: "integer", minimum: 1, maximum: 100, description: "Maximum number of hikes to return. Defaults to 20."}
          },
          required: []
        )
        annotations(title: "List my hikes", read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

        def self.handle(account:, scopes:, args:)
          ds = account.trips_dataset
          ds = ds.where(status: args[:status]) if %w[draft published].include?(args[:status])
          trips = ds.reverse_order(:hiked_at, :id).limit(args[:limit] || 20).all

          {count: trips.size, hikes: trips.map { |trip| trip_summary(trip) }}
        end
      end

      class GetHike < Base
        tool_name "get_hike"
        description "Fetch one of the member's hikes in full: stats, the trip report markdown, and every photo with captions and metadata. Useful for reading past reports to match the member's writing voice."
        input_schema(
          properties: {
            trip_id: {type: "integer", description: "The hike's id, from list_my_hikes or create_hike_draft."}
          },
          required: ["trip_id"]
        )
        annotations(title: "Get a hike", read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

        def self.handle(account:, scopes:, args:)
          trip_details(owned_trip!(account, args[:trip_id]))
        end
      end

      class CreateHikeDraft < Base
        tool_name "create_hike_draft"
        description "Create a new hike as a private draft. Nothing is public and nobody is notified until publish_hike is called. Returns the draft plus a photo_upload_url the member can open on their phone to add photos from their camera roll."
        input_schema(
          properties: {
            name: {type: "string", description: "Trip name, e.g. 'Goat Rocks Loop'."},
            hiked_at: {type: "string", description: "Date of the hike (first day if overnight), ISO 8601, e.g. 2026-07-18."},
            nights: {type: "integer", minimum: 0, description: "Nights spent out. 0 for a day hike."},
            mileage: {type: "number", minimum: 0, description: "Round-trip distance in miles."},
            elevation: {type: "integer", minimum: 0, description: "Elevation gain in feet."},
            lat: {type: "number", minimum: -90, maximum: 90, description: "Trailhead or trip latitude. Provide with lng or not at all."},
            lng: {type: "number", minimum: -180, maximum: 180, description: "Trailhead or trip longitude. Provide with lat or not at all."},
            source_url: {type: "string", description: "Optional reference link (trail guide, route page)."},
            report_markdown: {type: "string", description: "The trip report, in markdown. Can start empty and grow via update_hike."}
          }.merge(flag_properties),
          required: %w[name hiked_at]
        )
        annotations(title: "Create a hike draft", read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: false)

        def self.handle(account:, scopes:, args:)
          require_write!(scopes)

          name = args[:name].to_s.strip
          raise ToolError, "name cannot be blank." if name.empty?
          if args.key?(:lat) ^ args.key?(:lng)
            raise ToolError, "Provide both lat and lng, or neither."
          end

          attributes = {
            account_id: account.id,
            name: name,
            slug: Slug.generate(name),
            hiked_at: parse_hiked_at!(args[:hiked_at]),
            nights: args[:nights] || 0,
            mileage: args[:mileage],
            elevation: args[:elevation],
            lat: args[:lat],
            lng: args[:lng],
            source_url: presence(args[:source_url]),
            report_markdown: args[:report_markdown].to_s,
            status: "draft",
            published_at: nil
          }
          apply_flag_args!(args, attributes)

          trip = Models::Trip.create(attributes)

          trip_details(trip).merge(upload_link(trip))
        end

        def self.presence(value)
          value.to_s.strip.empty? ? nil : value.to_s.strip
        end

        def self.upload_link(trip)
          {
            photo_upload_url: UploadTokens.upload_url(trip),
            photo_upload_url_expires_at: UploadTokens.expires_at.iso8601,
            next_steps: "Share photo_upload_url with the member so they can add photos from their phone. After they say they are done, call get_hike to see the uploaded photos."
          }
        end
      end

      class UpdateHike < Base
        tool_name "update_hike"
        description "Update fields on one of the member's hikes. Only the fields provided are changed. Works on drafts and published hikes; edits to published hikes are visible immediately."
        input_schema(
          properties: {
            trip_id: {type: "integer", description: "The hike's id."},
            name: {type: "string"},
            hiked_at: {type: "string", description: "ISO 8601 date."},
            nights: {type: "integer", minimum: 0},
            mileage: {type: "number", minimum: 0},
            elevation: {type: "integer", minimum: 0},
            lat: {type: "number", minimum: -90, maximum: 90},
            lng: {type: "number", minimum: -180, maximum: 180},
            source_url: {type: "string"},
            report_markdown: {type: "string", description: "Replaces the whole report, so include the full text."}
          }.merge(flag_properties),
          required: ["trip_id"]
        )
        annotations(title: "Update a hike", read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

        def self.handle(account:, scopes:, args:)
          require_write!(scopes)
          trip = owned_trip!(account, args[:trip_id])

          updates = {}
          if args.key?(:name)
            name = args[:name].to_s.strip
            raise ToolError, "name cannot be blank." if name.empty?

            updates[:name] = name
            updates[:slug] = Slug.generate(name) if trip.draft?
          end
          updates[:hiked_at] = parse_hiked_at!(args[:hiked_at]) if args.key?(:hiked_at)
          updates[:nights] = args[:nights] if args.key?(:nights)
          updates[:mileage] = args[:mileage] if args.key?(:mileage)
          updates[:elevation] = args[:elevation] if args.key?(:elevation)
          updates[:source_url] = args[:source_url].to_s.strip.empty? ? nil : args[:source_url].to_s.strip if args.key?(:source_url)
          updates[:report_markdown] = args[:report_markdown].to_s if args.key?(:report_markdown)
          apply_flag_args!(args, updates)

          if args.key?(:lat) || args.key?(:lng)
            raise ToolError, "Provide both lat and lng together." unless args.key?(:lat) && args.key?(:lng)

            updates[:lat] = args[:lat]
            updates[:lng] = args[:lng]
          end

          raise ToolError, "Nothing to update. Provide at least one field." if updates.empty?

          trip.update(updates)
          trip_details(trip)
        end
      end

      class SetPhotoCaption < Base
        tool_name "set_photo_caption"
        description "Set or clear the caption on one of the hike's photos. Pass an empty caption to clear it."
        input_schema(
          properties: {
            trip_id: {type: "integer", description: "The hike's id."},
            photo_id: {type: "integer", description: "The photo's id, from get_hike."},
            caption: {type: "string", description: "The caption text. Empty string clears the caption."}
          },
          required: %w[trip_id photo_id caption]
        )
        annotations(title: "Set a photo caption", read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

        def self.handle(account:, scopes:, args:)
          require_write!(scopes)
          trip = owned_trip!(account, args[:trip_id])
          photo = trip.photos_dataset.where(id: args[:photo_id].to_i).first
          raise ToolError, "No photo with id #{args[:photo_id]} on that hike. Call get_hike to list its photos." unless photo

          caption = args[:caption].to_s.strip
          photo.update(caption: caption.empty? ? nil : caption)
          photo_details(photo)
        end
      end

      class GetPhotoUploadLink < Base
        tool_name "get_photo_upload_link"
        description "Get a fresh, short-lived link the member can open on their phone to upload photos from their camera roll straight onto a hike. Share the link with the member; after they finish uploading, call get_hike to see the photos."
        input_schema(
          properties: {
            trip_id: {type: "integer", description: "The hike's id."}
          },
          required: ["trip_id"]
        )
        annotations(title: "Get a photo upload link", read_only_hint: true, destructive_hint: false, idempotent_hint: false, open_world_hint: false)

        def self.handle(account:, scopes:, args:)
          require_write!(scopes)
          trip = owned_trip!(account, args[:trip_id])

          {
            trip_id: trip.id,
            name: trip.name,
            photo_upload_url: UploadTokens.upload_url(trip),
            expires_at: UploadTokens.expires_at.iso8601,
            note: "The link works for about two hours and only for this hike."
          }
        end
      end

      class PublishHike < Base
        tool_name "publish_hike"
        description "Publish a draft hike. This makes it public on Went Hiking and queues email notifications to the member's followers, so ALWAYS confirm with the member immediately before calling this. Returns the public URL."
        input_schema(
          properties: {
            trip_id: {type: "integer", description: "The draft hike's id."}
          },
          required: ["trip_id"]
        )
        annotations(title: "Publish a hike", read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: true)

        def self.handle(account:, scopes:, args:)
          require_write!(scopes)
          trip = owned_trip!(account, args[:trip_id])
          if trip.published?
            return {trip_id: trip.id, status: "published", url: public_url(trip.public_path), note: "This hike was already published."}
          end

          name = trip.name.to_s.strip
          raise ToolError, "Give the hike a real name before publishing." if name.empty? || name == "Untitled Hike"
          raise ToolError, "Set hiked_at before publishing." unless trip.hiked_at

          trip.update(slug: Slug.generate(name), status: "published", published_at: Time.now)
          HikeNotificationScheduler.schedule_trip(trip)

          {
            trip_id: trip.id,
            status: trip.status,
            url: public_url(trip.public_path),
            note: "Published. Followers will be emailed on the site's normal notification schedule."
          }
        end
      end

      ALL = [
        ListMyHikes,
        GetHike,
        CreateHikeDraft,
        UpdateHike,
        SetPhotoCaption,
        GetPhotoUploadLink,
        PublishHike
      ].freeze
    end
  end
end

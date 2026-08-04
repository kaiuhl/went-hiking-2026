# frozen_string_literal: true

require "mcp"
require "went_hiking/models"
require "went_hiking/mcp/tools"

module WentHiking
  module Mcp
    READ_SCOPE = "hikes:read"
    WRITE_SCOPE = "hikes:write"
    SCOPES = [READ_SCOPE, WRITE_SCOPE].freeze

    INSTRUCTIONS = <<~TEXT
      Went Hiking is a community site for sharing hiking trip reports and trail
      photos. These tools act on behalf of the signed-in member.

      The posting workflow: create a hike as a draft, use search_places to
      find where it happened (every hike needs a location before it can
      publish — pass the chosen place_slug so the byline gets a real name),
      share the photo upload link so the member can add photos from their
      camera roll, iterate on the trip report together, then publish. Drafts
      are private; publishing makes the hike public and emails the member's
      followers, so always confirm with the member before calling
      publish_hike. Before drafting a report, it can help to fetch one or two
      of the member's past hikes to match their writing voice.

      Trip reports are markdown. Uploaded photos can be embedded inline with
      their handle (for example {{ photo:123 }}); photos that are not embedded
      appear in a gallery below the report.
    TEXT

    module_function

    def build_server(account:, scopes:)
      MCP::Server.new(
        name: "went-hiking",
        title: "Went Hiking",
        version: "1.0.0",
        instructions: INSTRUCTIONS,
        website_url: WentHiking.public_base_url,
        tools: Tools::ALL,
        server_context: {account: account, scopes: scopes}
      )
    end
  end
end

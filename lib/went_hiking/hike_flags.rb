# frozen_string_literal: true

module WentHiking
  # The optional condition flags an author can tap while composing a hike:
  # quick observations from the day (bugs, blooms, snow) that a future
  # conditions search can lean on. Each flag is a nullable string column on
  # trips holding one of the tokens below; NULL means the author didn't say,
  # which is a different fact from "none".
  #
  # Tokens are neutral spellings so the words shown in the editor (chip) and
  # on the published page (published) can be reworded without a data
  # migration. This module is the single vocabulary: the compose form, form
  # validation, autosave, the published byline, and the MCP tools all read
  # from it, so adding a flag is one migration plus one entry here.
  module HikeFlags
    Option = Struct.new(:token, :chip, :published)

    Flag = Struct.new(:key, :label, :options) do
      def tokens
        options.map(&:token)
      end

      def published_for(token)
        options.find { |option| option.token == token }&.published
      end
    end

    ALL = [
      Flag.new(
        key: :beauty,
        label: "Beauty",
        options: [
          Option.new(token: "pretty", chip: "pretty", published: "pretty"),
          Option.new(token: "beautiful", chip: "beautiful", published: "beautiful"),
          Option.new(token: "sublime", chip: "sublime", published: "sublime")
        ]
      ),
      Flag.new(
        key: :mosquitoes,
        label: "Mosquitoes",
        options: [
          Option.new(token: "none", chip: "none", published: "no mosquitoes"),
          Option.new(token: "some", chip: "some", published: "some mosquitoes"),
          Option.new(token: "swarms", chip: "swarms", published: "mosquito swarms")
        ]
      ),
      Flag.new(
        key: :wildflowers,
        label: "Wildflowers",
        options: [
          Option.new(token: "none", chip: "none", published: "no wildflowers"),
          Option.new(token: "blooming", chip: "blooming", published: "wildflowers blooming"),
          Option.new(token: "off_season", chip: "wrong season", published: "wildflowers out of season")
        ]
      ),
      Flag.new(
        key: :swimming,
        label: "Swimming",
        options: [
          Option.new(token: "none", chip: "none", published: "no swimming"),
          Option.new(token: "swam", chip: "swam", published: "swam"),
          Option.new(token: "off_season", chip: "too cold", published: "too cold to swim")
        ]
      ),
      Flag.new(
        key: :snow,
        label: "Snow",
        options: [
          Option.new(token: "none", chip: "none", published: "no snow"),
          Option.new(token: "patches", chip: "patches", published: "snow patches"),
          Option.new(token: "snowbound", chip: "snowbound", published: "snowbound")
        ]
      ),
      Flag.new(
        key: :crowds,
        label: "Crowds",
        options: [
          Option.new(token: "solitude", chip: "solitude", published: "solitude"),
          Option.new(token: "some_company", chip: "some company", published: "some company"),
          Option.new(token: "crowded", chip: "crowded", published: "crowded")
        ]
      )
    ].freeze

    BY_KEY = ALL.each_with_object({}) { |flag, memo| memo[flag.key] = flag }.freeze

    module_function

    def all
      ALL
    end

    def keys
      ALL.map(&:key)
    end

    def fetch(key)
      BY_KEY.fetch(key.to_sym)
    end

    def label(key)
      fetch(key).label
    end

    def valid?(key, token)
      fetch(key).tokens.include?(token)
    end
  end
end

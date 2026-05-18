# frozen_string_literal: true

require "redcarpet"
require "sanitize"

module WentHiking
  class Markdown
    SANITIZE_CONFIG = Sanitize::Config.merge(
      Sanitize::Config::RELAXED,
      elements: Sanitize::Config::RELAXED[:elements] + %w[figure figcaption],
      attributes: {
        all: %w[class],
        "a" => %w[href title rel],
        "img" => %w[src alt title width height loading],
        "code" => %w[class]
      },
      protocols: {
        "a" => {"href" => ["http", "https", "mailto", :relative]},
        "img" => {"src" => ["http", "https", :relative]}
      }
    ).freeze

    def initialize
      @renderer = Redcarpet::Markdown.new(
        Redcarpet::Render::HTML.new(
          filter_html: true,
          hard_wrap: false,
          link_attributes: {rel: "nofollow ugc"}
        ),
        autolink: true,
        fenced_code_blocks: true,
        no_intra_emphasis: true,
        space_after_headers: true,
        strikethrough: true,
        tables: true
      )
    end

    def render(text)
      Sanitize.fragment(@renderer.render(text.to_s), SANITIZE_CONFIG)
    end
  end
end

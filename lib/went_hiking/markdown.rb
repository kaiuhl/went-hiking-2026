# frozen_string_literal: true

require "redcarpet"
require "sanitize"

module WentHiking
  class Markdown
    # Elements whose contents are machinery rather than prose.
    REMOVE_CONTENTS = %w[iframe noembed noframes noscript script style].freeze

    # Redcarpet's filter_html removes the tag and keeps what was between it,
    # which publishes a pasted <style> block as a paragraph of CSS in the middle
    # of a trip report. It does that in C, before Sanitize is ever handed an
    # element to remove, so the source is the only place left to do it;
    # remove_contents below is the second gate, for any path where one of these
    # does survive as an element.
    #
    # The trade is that a code sample containing a literal <script> or <style>
    # tag loses it. A hiking journal has never had one.
    SCRIPT_OR_STYLE = %r{<\s*(script|style)\b[^>]*>.*?(?:<\s*/\s*\1\s*>|\z)}mi

    # Sanitize's RELAXED list allows <style> outright — it sanitises the CSS
    # inside rather than refusing the element — so subtracting the machinery
    # elements is what stops one arriving here from being passed straight
    # through. Redcarpet happened to strip them first, which is a thin thing to
    # have been relying on.
    SANITIZE_CONFIG = Sanitize::Config.merge(
      Sanitize::Config::RELAXED,
      remove_contents: REMOVE_CONTENTS,
      elements: Sanitize::Config::RELAXED[:elements] - REMOVE_CONTENTS + %w[figure figcaption],
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
      Sanitize.fragment(@renderer.render(text.to_s.gsub(SCRIPT_OR_STYLE, "")), SANITIZE_CONFIG)
    end
  end
end

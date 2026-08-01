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

    EXTENSIONS = {
      autolink: true,
      fenced_code_blocks: true,
      no_intra_emphasis: true,
      space_after_headers: true,
      strikethrough: true,
      tables: true
    }.freeze

    MAX_HEADING_LEVEL = 6

    # Counts nothing but heading levels, and does it by handing the source to
    # the same parser that will render it. A regex would call the "# rm -rf"
    # inside a fenced code block a heading; the parser calls that block_code and
    # never reaches here, which is the whole reason to pay for a second parse.
    class HeadingScan < Redcarpet::Render::Base
      def self.levels(text)
        scanner = new
        Redcarpet::Markdown.new(scanner, EXTENSIONS).render(text)
        scanner.levels
      end

      attr_reader :levels

      def initialize
        super
        @levels = []
      end

      def header(_text, level)
        @levels << level
        ""
      end
    end

    # A trip page's h1 is the trip's name and a comment lives under the section's
    # h2, so a body that opens with "# Somewhere" puts a second h1 on the page —
    # at --text-display size, halfway down an article. Headings move down a level
    # on the way out; report_markdown on disk keeps the "#" it was written with.
    class Renderer < Redcarpet::Render::HTML
      def initialize(options)
        @demote_below = options.delete(:demote_below) || 1
        super
      end

      def header(text, level)
        level = [level + 1, MAX_HEADING_LEVEL].min if level < @demote_below
        "\n<h#{level}>#{text}</h#{level}>\n"
      end
    end

    # How far down the demotion reaches, as the first level that stays put.
    # An h1 always becomes an h2; the levels under it only move when they would
    # otherwise be landed on, so a report of "# Trip" and "## Day one" keeps the
    # two apart instead of flattening both into h2. A body with no h1 is already
    # shaped for the page and is left exactly as written.
    def self.demote_below(text)
      levels = HeadingScan.levels(text.to_s.gsub(SCRIPT_OR_STYLE, ""))
      return 1 unless levels.include?(1)

      level = 1
      level += 1 while level < MAX_HEADING_LEVEL && levels.include?(level + 1)
      level + 1
    end

    def initialize
      @renderers = {}
    end

    # Callers holding a whole document that they render in pieces — a trip report
    # split around its photo handles — pass the demotion they worked out from the
    # whole thing, so a "# Trip" in one piece and a "## Day one" in the next agree
    # on what they are.
    def render(text, demote_below: nil)
      source = text.to_s.gsub(SCRIPT_OR_STYLE, "")
      Sanitize.fragment(renderer(demote_below || self.class.demote_below(source)).render(source), SANITIZE_CONFIG)
    end

    private

    def renderer(demote_below)
      @renderers[demote_below] ||= Redcarpet::Markdown.new(
        Renderer.new(
          filter_html: true,
          hard_wrap: false,
          link_attributes: {rel: "nofollow ugc"},
          demote_below: demote_below
        ),
        EXTENSIONS
      )
    end
  end
end

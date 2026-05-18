# frozen_string_literal: true

module WentHiking
  module Slug
    module_function

    def generate(value)
      value.to_s
        .downcase
        .gsub(/&/, " and ")
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/^-|-$/, "")
        .then { |slug| slug.empty? ? "untitled" : slug }
    end

    def id_slug(id, value)
      "#{id}-#{generate(value)}"
    end

    def extract_id(id_slug)
      id_slug.to_s[/\A\d+/]&.to_i
    end
  end
end

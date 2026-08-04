# frozen_string_literal: true

# The gazetteer: place data, name normalization, and geometry helpers, ported
# from Big Fluffy Puffy's places layer. Postgres-only at the storage level —
# an sqlite boot never requires this file.
module WentHiking
  module Places
    # How far a pin can move from its chosen place before the place's name
    # stops being true. The compose editor carries the same constant in
    # editor.js for the client-side half of the rule.
    PLACE_DETACH_KM = 20
  end
end

require_relative "places/models"
require_relative "places/normalizer"
require_relative "places/geometry"
require_relative "places/states"
require_relative "places/searcher"
require_relative "places/trip_locator"

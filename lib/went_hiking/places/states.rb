# frozen_string_literal: true

module WentHiking
  module Places
    # State names and codes, both directions: importers fall back to the name
    # when a source has no state column, and search subtitles spell the code
    # back out. All 50 plus DC, because the gazetteer is national by config.
    module States
      NAMES_BY_CODE = {
        "al" => "Alabama", "ak" => "Alaska", "az" => "Arizona", "ar" => "Arkansas",
        "ca" => "California", "co" => "Colorado", "ct" => "Connecticut", "de" => "Delaware",
        "dc" => "District of Columbia", "fl" => "Florida", "ga" => "Georgia", "hi" => "Hawaii",
        "id" => "Idaho", "il" => "Illinois", "in" => "Indiana", "ia" => "Iowa",
        "ks" => "Kansas", "ky" => "Kentucky", "la" => "Louisiana", "me" => "Maine",
        "md" => "Maryland", "ma" => "Massachusetts", "mi" => "Michigan", "mn" => "Minnesota",
        "ms" => "Mississippi", "mo" => "Missouri", "mt" => "Montana", "ne" => "Nebraska",
        "nv" => "Nevada", "nh" => "New Hampshire", "nj" => "New Jersey", "nm" => "New Mexico",
        "ny" => "New York", "nc" => "North Carolina", "nd" => "North Dakota", "oh" => "Ohio",
        "ok" => "Oklahoma", "or" => "Oregon", "pa" => "Pennsylvania", "ri" => "Rhode Island",
        "sc" => "South Carolina", "sd" => "South Dakota", "tn" => "Tennessee", "tx" => "Texas",
        "ut" => "Utah", "vt" => "Vermont", "va" => "Virginia", "wa" => "Washington",
        "wv" => "West Virginia", "wi" => "Wisconsin", "wy" => "Wyoming"
      }.freeze

      CODES_BY_NAME = NAMES_BY_CODE.invert.transform_keys(&:downcase).freeze

      def self.name_for(code)
        NAMES_BY_CODE[code.to_s.downcase]
      end

      def self.code_for(name)
        CODES_BY_NAME[name.to_s.downcase]
      end
    end
  end
end

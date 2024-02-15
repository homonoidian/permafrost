require "./permafrost/core/*"
require "./permafrost/map"
require "./permafrost/set"
require "./permafrost/bidi_map"
require "./permafrost/ext"

module Pf
  VERSION = "0.1.3"

  # :nodoc:
  module Core
    macro hash64(object)
      ({{object}}).hash
    end
  end
end

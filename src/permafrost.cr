require "./permafrost/core/*"
require "./permafrost/error"
require "./permafrost/map"
require "./permafrost/set"
require "./permafrost/bidi_map"
require "./permafrost/ext"

module Pf
  VERSION = "0.2.0"

  # :nodoc:
  module Core
    macro hash64(object)
      ({{object}}).hash
    end

    macro fiber_id
      ::Fiber.current.object_id
    end
  end
end

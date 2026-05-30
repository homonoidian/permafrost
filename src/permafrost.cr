require "./permafrost/kit"
require "./permafrost/error"
require "./permafrost/map"
require "./permafrost/set"
require "./permafrost/bidi_map"
require "./permafrost/uset32"
require "./permafrost/block_list"
require "./permafrost/upath32"
require "./permafrost/bit_set"
require "./permafrost/grapheme_view"
require "./permafrost/grapheme_seln"
require "./permafrost/ext"

module Pf
  VERSION = "0.13.2"

  # :nodoc:
  macro hash64(object)
    ({{object}}).hash
  end

  # :nodoc:
  macro fiber_id
    ::Fiber.current.object_id
  end

  # Auxiliary data structures.
  module Kit
  end
end

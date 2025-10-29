require "./permafrost/core/*"
require "./permafrost/error"
require "./permafrost/map"
require "./permafrost/set"
require "./permafrost/bidi_map"
require "./permafrost/uset32"
require "./permafrost/ext"

module Pf
  VERSION = "0.5.0"

  # :nodoc:
  macro hash64(object)
    ({{object}}).hash
  end

  # :nodoc:
  macro fiber_id
    ::Fiber.current.object_id
  end

  # If you don't like `Pf::Map`, `Pf::Set`, etc., or they aren't performant enough
  # for you, you can build your own map/set/HAMT-like thingy using `Node`, writing
  # probe implementations that satisfy the corresponding interfaces (see, for instance,
  # `IProbeAdd`, `IProbeFetch`, etc).
  #
  # For an example of how to use `Node` look into the source code of `Pf::Map`
  # or `Pf::Set`.
  module Core
  end
end

# An immutable vector of `UInt32`s with tree path-specific optimizations.
struct Pf::UPath32
  include Enumerable(UInt32)

  # :nodoc:
  alias UInt96 = Kit::UInt96

  # :nodoc:
  alias Any = Index | Dense | Sparse

  # NOTE: The idea here is not to have a single empty variant, but to have each
  # member of `Any` (each internal repr of a UPath32) have *its own* empty variant.
  # This means we're avoiding (in an odd way, I suppose) the problem of mandatory
  # normalization: we don't have to constantly ask questions like "... Is it empty?
  # Then make it Empty ...", and have weird edge cases around them.

  # :nodoc:
  #
  # Index optimizes singleton UPath32's, which can be encountered when one uses
  # `UPath32` as an index, or when it happens to be used as one (e.g. skipping over
  # root terms during DFS or BFS).
  alias Index = IndexEmpty | IndexNonempty

  # :nodoc:
  record IndexEmpty

  # :nodoc:
  record IndexNonempty, n : UInt32

  # :nodoc:
  DENSECAP = 16u32

  # :nodoc:
  #
  # As an optimization, we store small paths inline, packing them in 96 bits. It
  # is 96 because if it was 64, we'd inevitably lose 32 bits to alignment. So we
  # use those 32 bits to prevent even more heap allocations instead!
  #
  # Paths that have more than DENSECAP n's, or those with n's out of bounds for
  # their respective slot, are transferred to the GC heap (`Sparse`).
  #
  # - The first n receives 11 bits, because nodes near the root are usually large.
  # - Successive n's receive a smaller number of bits, because nodes closer to
  #   the root are expected to be large, but smaller than their predecessor.
  # - The remaining n's receive 4 bits, because deep nodes are expected to
  #   be small.
  #
  # ```text
  #                 2x 11-bits                              8x 7-bits                    8x 4-bits
  #         ┌───────────────────────┐                   ┌───────────────┐           ┌─────────────────┐
  #
  #         ┌───────────┬───────────┬─────────┬─────────┬───────┬───────┬─────┬─────┬────┐       ┌────┐
  #    LSB  │           │           │         │         │       │       │     │     │    │ . . . │    │  MSB
  #         └───────────┴───────────┴─────────┴─────────┴───────┴───────┴─────┴─────┴────┘       └────┘
  #
  #                                 └───────────────────┘               └───────────┘
  #                                        2x 9-bits                       2x 5-bits
  # │                                                                                                         │
  # └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
  #
  #                                                   96 bits
  # ```
  record Dense, bits : UInt96, size : UInt32

  # :nodoc:
  #
  # An pathstored on GC heap.
  alias Sparse = Slice(UInt32)

  # :nodoc:
  def initialize(@path : Any)
  end

  # Constructs an empty path.
  def self.[] : UPath32
    new(IndexEmpty.new)
  end

  def self.[](*ns : UInt32) : UPath32
    ns.reduce(UPath32[]) { |path, n| path.append(n) }
  end

  # :nodoc:
  def self.offset(size : UInt32) : UInt32
    case size
    when 0u32            then 11u32*0 + 9u32*0 + 7u32*0 + 5u32*0 + 4u32*0
    when 1u32            then 11u32*1 + 9u32*0 + 7u32*0 + 5u32*0 + 4u32*0
    when 2u32            then 11u32*2 + 9u32*0 + 7u32*0 + 5u32*0 + 4u32*0
    when 3u32            then 11u32*2 + 9u32*1 + 7u32*0 + 5u32*0 + 4u32*0
    when 4u32            then 11u32*2 + 9u32*2 + 7u32*0 + 5u32*0 + 4u32*0
    when 5u32            then 11u32*2 + 9u32*2 + 7u32*1 + 5u32*0 + 4u32*0
    when 6u32            then 11u32*2 + 9u32*2 + 7u32*2 + 5u32*0 + 4u32*0
    when 7u32            then 11u32*2 + 9u32*2 + 7u32*2 + 5u32*1 + 4u32*0
    when 8u32            then 11u32*2 + 9u32*2 + 7u32*2 + 5u32*2 + 4u32*0
    when 9u32...DENSECAP then 11u32*2 + 9u32*2 + 7u32*2 + 5u32*2 + 4u32*(size - 8u32)
    else
      raise ArgumentError.new
    end
  end

  # :nodoc:
  def self.width(size : UInt32) : UInt32
    case size
    when 0u32            then 11u32
    when 1u32            then 11u32
    when 2u32            then 9u32
    when 3u32            then 9u32
    when 4u32            then 7u32
    when 5u32            then 7u32
    when 6u32            then 5u32
    when 7u32            then 5u32
    when 8u32...DENSECAP then 4u32
    else
      raise ArgumentError.new
    end
  end

  # :nodoc:
  def self.max(size : UInt32) : UInt32
    case size
    when 0u32            then 2u32**11
    when 1u32            then 2u32**11
    when 2u32            then 2u32**9
    when 3u32            then 2u32**9
    when 4u32            then 2u32**7
    when 5u32            then 2u32**7
    when 6u32            then 2u32**5
    when 7u32            then 2u32**5
    when 8u32...DENSECAP then 2u32**4
    else
      0u32
    end
  end

  # TODO: demote? for path : Dense, gain = 0.
  # TODO:
  #   If path.size + gain <= 1
  #     if path.size == 0
  #       return IndexEmpty
  #     if path.size == 1
  #       return IndexNonempty
  #     else
  #       return Dense
  private def self.demote?(path : Sparse, gain = 0) : Dense?
    return unless path.size + gain <= DENSECAP

    bits = UInt96.zero

    path.each_with_index do |n, index|
      return unless n < max(index.to_u32)

      bits |= UInt96.new(n.to_u128) << offset(index.to_u32)
    end

    Dense.new(bits, path.size.to_u32)
  end

  # :nodoc:
  def self.append(path : IndexEmpty, n : UInt32) : Any
    IndexNonempty.new(n)
  end

  # :nodoc:
  def self.append(path : IndexNonempty, n : UInt32) : Any
    dense = Dense.new(bits: UInt96.zero, size: 0u64)

    append(append(dense, path.n), n)
  end

  # :nodoc:
  def self.append(path : Dense, n : UInt32) : Any
    unless n < max(path.size) # Does not fit, move to heap.
      ns = Sparse.new(path.size + 1, read_only: true)
      i = 0

      each(path) do |n|
        ns.unsafe_put(i, n)
        i += 1
      end
      ns.unsafe_put(i, n)

      return ns
    end

    mask = UInt96.new(n.to_u128) << offset(path.size)

    Dense.new(path.bits | mask, path.size + 1)
  end

  # :nodoc:
  def self.append(path : Sparse, n : UInt32) : Any
    if n < max(path.size.to_u32)
      if dense = demote?(path, gain: 1)
        return append(dense, n)
      end
    end

    mem = Pointer(T).malloc(path.size + 1)
    mem.copy_from(path.to_unsafe, path.size)
    mem[path.size] = n

    Slice.new(mem, path.size + 1, read_only: true)
  end

  # :nodoc:
  def self.prepend(path : IndexEmpty, n : UInt32) : Any
    IndexNonempty.new(n)
  end

  # :nodoc:
  def self.prepend(path : IndexNonempty, n : UInt32) : Any
    dense = Dense.new(bits: UInt96.zero, size: 0u64)

    prepend(prepend(dense, path.n), n)
  end

  # :nodoc:
  def self.prepend(path : Dense, n : UInt32) : Any
    bits = UInt96.new(n.to_u128) << offset(0u32)
    slot = 1u32

    each(path) do |item|
      if item < max(slot) # Item fits in the next slot.
        bits |= UInt96.new(item.to_u128) << offset(slot)
        slot += 1
        next
      end

      # Item does not fit in the next slot.
      ns = Sparse.new(path.size + 1, read_only: true)
      ns.unsafe_put(0, n)

      i = 1
      each(path) do |n|
        ns.unsafe_put(i, n)
        i += 1
      end

      return ns
    end

    Dense.new(bits, path.size + 1)
  end

  # :nodoc:
  def self.prepend(path : Sparse, n : UInt32) : Any
    if n < max(0u32)
      # NOTE: prepend below will copy all ns anyway. Demotion is simply a bit
      # of possibly useless work; if the slow path is taken, it'll also simply
      # copy all ns.
      if dense = demote?(path, gain: 1)
        return prepend(dense, n)
      end
    end

    mem = Pointer(T).malloc(path.size + 1)
    mem[0] = object
    (mem + 1).copy_from(path.to_unsafe, path.size)

    Slice.new(mem, path.size + 1, read_only: true)
  end

  # :nodoc:
  def self.each(path : IndexEmpty, & : UInt32 ->) : Nil
  end

  # :nodoc:
  def self.each(path : IndexNonempty, & : UInt32 ->) : Nil
    yield path.n
  end

  # :nodoc:
  def self.each(path : Dense, & : UInt32 ->) : Nil
    offset = 0u32

    path.size.times do |index|
      width = width(index)
      mask = ((UInt96.new(1) << width) &- 1) << offset
      yield ((path.bits & mask) >> offset).to_u32

      offset += width
    end
  end

  # :nodoc:
  def self.each(path : Sparse, & : UInt32 ->) : Nil
    path.each { |n| yield n }
  end

  # :nodoc:
  def self.tip?(path : IndexEmpty) : UInt32?
  end

  # :nodoc:
  def self.tip?(path : IndexNonempty) : UInt32?
    path.n
  end

  # :nodoc:
  def self.tip?(path : Dense) : UInt32?
    return if path.size.zero?

    offset = offset(path.size &- 1)
    width = width(path.size &- 1)
    mask = ((UInt96.new(1) << width) &- 1) << offset

    ((path.bits & mask) >> offset).to_u32
  end

  # :nodoc:
  def self.tip?(path : Sparse) : UInt32?
    path.last?
  end

  # :nodoc:
  def self.prior(path : IndexEmpty) : IndexEmpty
    path
  end

  # :nodoc:
  def self.prior(path : IndexNonempty) : IndexEmpty
    IndexEmpty.new
  end

  # :nodoc:
  def self.prior(path : Dense) : Dense
    return path if path.size.zero?

    # Zero out the top slot.
    offset = offset(path.size &- 1)
    width = width(path.size &- 1)
    mask = ((UInt96.new(1) << width) &- 1) << offset

    Dense.new(path.bits & ~mask, path.size &- 1)
  end

  # :nodoc:
  def self.prior(path : Sparse) : Sparse
    return path if path.empty?

    # NOTE: we could demote Sparse to Dense here, but what's the point? Prior
    # is an integer decrement. It's better to demote in `move` and `append`,
    # which we do; because they're the ones who copy (as in, do real work) --
    # and they're the ones who'd like to avoid copying!
    Sparse.new(path.to_unsafe, path.size &- 1, read_only: true)
  end

  # :nodoc:
  def self.rest(path : IndexEmpty) : IndexEmpty
    path
  end

  # :nodoc:
  def self.rest(path : IndexNonempty) : IndexEmpty
    IndexEmpty.new
  end

  # :nodoc:
  def self.rest(path : Dense) : Dense
    return path if path.size.zero?

    bits = UInt96.zero
    slot = 0u32
    first = true

    each(path) do |n|
      if first
        first = false
        next
      end

      bits |= UInt96.new(n.to_u128) << offset(slot)
      slot += 1
    end

    Dense.new(bits, path.size - 1)
  end

  # :nodoc:
  def self.rest(path : Sparse) : Sparse
    return path if path.empty?

    # Ditto the NOTE above.
    path + 1
  end

  # :nodoc:
  def self.size(path : IndexEmpty) : UInt32
    0u32
  end

  # :nodoc:
  def self.size(path : IndexNonempty) : UInt32
    1u32
  end

  # :nodoc:
  def self.size(path : Dense) : UInt32
    path.size
  end

  # :nodoc:
  def self.size(path : Sparse) : UInt32
    path.size.to_u32
  end

  # :nodoc:
  def self.unsafe_fetch(path : IndexEmpty, index : UInt32) : UInt32
    raise ArgumentError.new
  end

  # :nodoc:
  def self.unsafe_fetch(path : IndexNonempty, index : UInt32) : UInt32
    assert index.zero?

    path.n
  end

  # :nodoc:
  def self.unsafe_fetch(path : Dense, index : UInt32) : UInt32
    offset = offset(index)
    width = width(index)
    mask = ((UInt96.new(1) << width) &- 1) << offset

    ((path.bits & mask) >> offset).to_u32
  end

  # :nodoc:
  def self.unsafe_fetch(path : Sparse, index : UInt32) : UInt32
    path.unsafe_fetch(index)
  end

  # Returns the number of ns in this path.
  def size : UInt32
    UPath32.size(@path)
  end

  # Yields each n in this path, left to right.
  def each(& : UInt32 ->)
    UPath32.each(@path) { |n| yield n }
  end

  # Returns the last n of this path (its *tip*), or `nil` if this path is empty.
  def tip? : UInt32?
    UPath32.tip?(@path)
  end

  # Returns the last n of this path (its *tip*), or raises `IndexError` if this
  # path is empty.
  def tip : UInt32
    tip? || raise IndexError.new
  end

  # Returns *index*-th n of this path.
  def []?(index : Int) : UInt32?
    return unless index < size

    UPath32.unsafe_fetch(@path, index.to_u32)
  end

  # Returns a subview of this path.
  def []?(range : Range) : UPath32?
    b, count = Indexable.range_to_index_and_count(range, size) || return
    e = b + count
    return if e > size

    path = self
    b.times do
      path = path.rest
    end

    (size - e).times do
      path = path.prior
    end

    path
  end

  # Calls one of the `[]?` overloads. Raises `IndexError` instead of returning `nil`.
  def [](object)
    self[object]? || raise IndexError.new
  end

  # Inserts *n* at the front of this path. Returns a modified copy.
  def prepend(n : UInt32) : UPath32
    UPath32.new(UPath32.prepend(@path, n))
  end

  # Inserts *n* at the back of this path. Returns a modified copy.
  def append(n : UInt32) : UPath32
    UPath32.new(UPath32.append(@path, n))
  end

  # Removes the first n of this path. Returns a modified copy. If this path
  # is empty, does nothing.
  def rest : UPath32
    UPath32.new(UPath32.rest(@path))
  end

  # Removes the last n of this path. Returns a modified copy. If this path
  # is empty, does nothing.
  def prior : UPath32
    UPath32.new(UPath32.prior(@path))
  end

  # Makes *n* the tip of this path. Returns a modified copy. If this path
  # is empty, does nothing.
  def goto(n : UInt32) : UPath32
    prior.append(n)
  end

  def inspect(io)
    io << "UPath32["
    join(io, "-")
    io << "]"
  end
end

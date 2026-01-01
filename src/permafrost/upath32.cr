module Pf
  # An immutable vector of `UInt32`s (here called *indices*) with tree path-
  # specific optimizations.
  #
  # ```
  # path = Pf::UPath32[100, 20]
  # path.append(3) # => UPath32[100, 20, 3]
  # path.append(7) # => UPath32[100, 20, 7]
  # path           # => UPath32[100, 20]
  # ```
  struct UPath32
    include Enumerable(UInt32)

    # :nodoc:
    alias Any = End | IndexEmpty | IndexNonempty | Dense | Sparse

    # :nodoc:
    record End

    # :nodoc:
    record IndexEmpty

    # :nodoc:
    record IndexNonempty, index : UInt32

    # :nodoc:
    record Dense, bits : UInt64, size : UInt32

    # :nodoc:
    class Sparse
      getter prior, steps

      def initialize(@prior : Dense, @steps : BlockList(UInt32))
      end

      def_equals_and_hash prior, steps
    end

    private TAG_SPARSE = 0u64
    private TAG_DENSE  = 1u64
    private TAG_INDEX  = 2u64
    private TAG_END    = 3u64

    private TAG_BITSIZE = 3u64
    private TAG_MASK    = (1u64 << TAG_BITSIZE) - 1

    private INDEX_KIND_EMPTY    = 0u64
    private INDEX_KIND_NONEMPTY = 1u64

    private INDEX_KIND_BITSIZE = 2u64
    private INDEX_KIND_MASK    = (1u64 << INDEX_KIND_BITSIZE) - 1

    private DENSE_SIZE_BITSIZE = 4u64
    private DENSE_SIZE_MASK    = (1u64 << DENSE_SIZE_BITSIZE) - 1

    # :nodoc:
    def initialize(@data : Void*)
    end

    # Constructs an empty path.
    def self.[] : UPath32
      new(pack(IndexEmpty.new))
    end

    def self.[](*ns : UInt32) : UPath32
      ns.reduce(UPath32[]) { |path, n| path.append(n) }
    end

    # Returns the sentinel End path.
    def self.end : UPath32
      new(pack(End.new))
    end

    # :nodoc:
    def self.pack(path : End) : Void*
      Pointer(Void).new(TAG_END)
    end

    # :nodoc:
    def self.pack(path : IndexEmpty) : Void*
      bits = INDEX_KIND_EMPTY
      bits <<= TAG_BITSIZE
      bits |= TAG_INDEX

      Pointer(Void).new(bits)
    end

    # :nodoc:
    def self.pack(path : IndexNonempty) : Void*
      bits = path.index.to_u64
      bits <<= INDEX_KIND_BITSIZE
      bits |= INDEX_KIND_NONEMPTY
      bits <<= TAG_BITSIZE
      bits |= TAG_INDEX

      Pointer(Void).new(bits)
    end

    # :nodoc:
    def self.pack(path : Dense) : Void*
      Kit.assert path.bits <= 2u64**(64 - TAG_BITSIZE - DENSE_SIZE_BITSIZE) - 1
      Kit.assert path.size <= 2u32**DENSE_SIZE_BITSIZE - 1

      bits = path.bits
      bits <<= 4
      bits |= path.size
      bits <<= TAG_BITSIZE
      bits |= TAG_DENSE

      Pointer(Void).new(bits)
    end

    # :nodoc:
    def self.pack(path : Sparse) : Void*
      data = path.as(Void*)
      Kit.assert (data.address & TAG_MASK).zero?

      Pointer(Void).new(data.address | TAG_SPARSE)
    end

    # :nodoc:
    def self.unpack(data : Void*) : Any
      bits = data.address

      case bits & TAG_MASK
      when TAG_SPARSE
        rawptr = Pointer(Void).new(bits & ~TAG_MASK)
        rawptr.as(Sparse)
      when TAG_DENSE
        bits >>= TAG_BITSIZE
        size = (bits & DENSE_SIZE_MASK).to_u32
        bits >>= DENSE_SIZE_BITSIZE

        Dense.new(bits, size)
      when TAG_INDEX
        bits >>= TAG_BITSIZE

        case bits & INDEX_KIND_MASK
        when INDEX_KIND_EMPTY
          bits >>= INDEX_KIND_BITSIZE
          Kit.assert bits.zero?

          IndexEmpty.new
        when INDEX_KIND_NONEMPTY
          bits >>= INDEX_KIND_BITSIZE
          Kit.assert bits <= UInt32::MAX

          IndexNonempty.new(bits.to_u32)
        else
          raise ArgumentError.new
        end
      when TAG_END
        bits >>= TAG_BITSIZE
        Kit.assert bits.zero?

        End.new
      else
        raise ArgumentError.new
      end
    end

    # :nodoc:
    #
    # NOTE: Although we allocate DENSE_SIZE_BITSIZE (4) bits (0-15), we can
    # only use values up to 8.
    DENSECAP = 8u64

    # :nodoc:
    def self.offset(size : UInt32) : UInt32
      case size
      when 0u32 then 14u32*0 + 9u32*0 + 8u32*0 + 6u32*0 + 4u32*0
      when 1u32 then 14u32*1 + 9u32*0 + 8u32*0 + 6u32*0 + 4u32*0
      when 2u32 then 14u32*1 + 9u32*1 + 8u32*0 + 6u32*0 + 4u32*0
      when 3u32 then 14u32*1 + 9u32*1 + 8u32*1 + 6u32*0 + 4u32*0
      when 4u32 then 14u32*1 + 9u32*1 + 8u32*1 + 6u32*1 + 4u32*0
      when 5u32 then 14u32*1 + 9u32*1 + 8u32*1 + 6u32*1 + 4u32*1
      when 6u32 then 14u32*1 + 9u32*1 + 8u32*1 + 6u32*1 + 4u32*2
      when 7u32 then 14u32*1 + 9u32*1 + 8u32*1 + 6u32*1 + 4u32*3
      else
        raise ArgumentError.new
      end
    end

    # :nodoc:
    def self.width(size : UInt32) : UInt32
      case size
      when 0u32 then 14u32
      when 1u32 then 9u32
      when 2u32 then 8u32
      when 3u32 then 6u32
      when 4u32 then 4u32
      when 5u32 then 4u32
      when 6u32 then 4u32
      when 7u32 then 4u32
      else
        raise ArgumentError.new
      end
    end

    # :nodoc:
    def self.max(size : UInt32) : UInt32
      case size
      when 0u32 then 2u32**14 - 1
      when 1u32 then 2u32**9 - 1
      when 2u32 then 2u32**8 - 1
      when 3u32 then 2u32**6 - 1
      when 4u32 then 2u32**4 - 1
      when 5u32 then 2u32**4 - 1
      when 6u32 then 2u32**4 - 1
      when 7u32 then 2u32**4 - 1
      else
        0u32
      end
    end

    # :nodoc:
    def self.tag?(bits : Void*, tag : UInt64) : Bool
      (bits.address & tag) == tag
    end

    # :nodoc:
    def self.usize(path : IndexEmpty | End) : UInt32
      0u32
    end

    # :nodoc:
    def self.usize(path : IndexNonempty) : UInt32
      1u32
    end

    # :nodoc:
    def self.usize(path : Dense) : UInt32
      path.size
    end

    # :nodoc:
    def self.usize(path : Sparse) : UInt32
      usize(path.prior) + path.steps.size
    end

    # :nodoc:
    def self.each(path : IndexEmpty | End, &)
    end

    # :nodoc:
    def self.each(path : IndexNonempty, &)
      yield path.index
    end

    # :nodoc:
    def self.each(path : Dense, &)
      offset = 0u32

      path.size.times do |index|
        width = width(index)
        mask = ((1u64 << width) - 1) << offset
        yield ((path.bits & mask) >> offset).to_u32

        offset += width
      end
    end

    # :nodoc:
    def self.each(path : Sparse, &)
      each(path.prior) { |step| yield step }

      path.steps.each { |step| yield step }
    end

    # :nodoc:
    def self.append(path : End, step : UInt32)
      path
    end

    # :nodoc:
    def self.append(path : IndexEmpty, step : UInt32)
      IndexNonempty.new(step)
    end

    # :nodoc:
    def self.append(path : IndexNonempty, step : UInt32)
      append(append(Dense.new(bits: 0u64, size: 0u32), path.index), step)
    end

    # :nodoc:
    def self.append(path : Dense, step : UInt32)
      unless step < max(path.size) # Does not fit, move to heap.
        return Sparse.new(path, BlockList[step])
      end

      mask = step.to_u64 << offset(path.size)

      Dense.new(bits: path.bits | mask, size: path.size + 1)
    end

    # :nodoc:
    def self.append(path : Sparse, step : UInt32)
      Sparse.new(path.prior, path.steps.append(step))
    end

    # :nodoc:
    def self.prior(path : End | IndexEmpty)
      path
    end

    # :nodoc:
    def self.prior(path : IndexNonempty)
      IndexEmpty.new
    end

    # :nodoc:
    def self.prior(path : Dense)
      if path.size.in?(0, 1)
        return IndexEmpty.new
      end

      # Zero out the top slot.
      offset = offset(path.size - 1)
      width = width(path.size - 1)
      mask = ((1u64 << width) - 1) << offset

      # Demote it further to IndexNonempty if possible.
      result = Dense.new(path.bits & ~mask, path.size - 1)
      if result.size == 1
        index = last?(result) || raise ArgumentError.new
        return IndexNonempty.new(index)
      end

      result
    end

    # :nodoc:
    def self.prior(path : Sparse)
      case path.steps.size
      when 0 then prior(path.prior) # This should not happen!
      when 1 then path.prior
      else
        Sparse.new(path.prior, path.steps.prior)
      end
    end

    # :nodoc:
    def self.last?(path : End | IndexEmpty) : UInt32?
    end

    # :nodoc:
    def self.last?(path : IndexNonempty) : UInt32?
      path.index
    end

    # :nodoc:
    def self.last?(path : Dense) : UInt32?
      return if path.size.zero?

      offset = offset(path.size - 1)
      width = width(path.size - 1)
      mask = ((1u64 << width) - 1) << offset

      ((path.bits & mask) >> offset).to_u32
    end

    # :nodoc:
    def self.last?(path : Sparse) : UInt32?
      path.steps.last? || last?(path.prior)
    end

    # :nodoc:
    def self.fetch?(path : End | IndexEmpty, index : UInt32) : UInt32?
    end

    # :nodoc:
    def self.fetch?(path : IndexNonempty, index : UInt32) : UInt32?
      index.zero? ? path.index : nil
    end

    # :nodoc:
    def self.fetch?(path : Dense, index : UInt32) : UInt32?
      return unless index < path.size

      offset = offset(index)
      width = width(index)
      mask = ((1u64 << width) - 1) << offset

      ((path.bits & mask) >> offset).to_u32
    end

    # :nodoc:
    def self.fetch?(path : Sparse, index : UInt32) : UInt32?
      if index < path.prior.size
        return fetch?(path.prior, index)
      end

      # index >= path.prior.size
      path.steps[index - path.prior.size]?
    end

    # Returns `true` if this path is the sentinel End path.
    #
    # Sentinel `End` marker useful in traversals that must distinguish entering
    # the root from reentering it at the end of traversal.
    def end? : Bool
      UPath32.tag?(@data, TAG_END)
    end

    # Returns `true` if the underlying representation of this path is an index.
    #
    # Index optimizes singleton UPath32's, which can be encountered when one uses
    # `UPath32` as an index, or when it happens to be used as one (e.g. skipping over
    # root terms during DFS or BFS).
    def index? : Bool
      UPath32.tag?(@data, TAG_INDEX)
    end

    # Returns `true` if the underlying representation of this path is dense.
    #
    # As an optimization, we store small paths inline, packing them in 57 bits plus
    # 4-bit size.
    #
    # The shape of the "path gamut" for this representation is currently `14-9-8-6-4-4-4-4`.
    # Paths that are outside of this "gamut" are transferred to (or constructed on)
    # the GC heap (`sparse?`).
    #
    # - The first index receives a larger number of bits, because indices near the root
    #   are usually large.
    # - Successive indices receive a smaller number of bits, because nodes closer
    #   to the root are expected to be large, but smaller than their predecessor.
    def dense? : Bool
      UPath32.tag?(@data, TAG_DENSE)
    end

    # Returns `true` if the underlying representation of this path is sparse.
    #
    # Sparse paths are stored on the GC heap.
    def sparse? : Bool
      UPath32.tag?(@data, TAG_SPARSE)
    end

    # Returns the number of indices in this path as an index within zero
    # or positive `Int32` bounds.
    def size : Int32
      usize.to_i
    end

    # Returns the number of indices in this path as an index within `UInt32` bounds.
    def usize : UInt32
      UPath32.usize(UPath32.unpack(@data))
    end

    # Yields each index in this path in front-to-back order.
    def each(& : UInt32 ->)
      UPath32.each(UPath32.unpack(@data)) { |step| yield step }
    end

    # Returns the part of this path before the last index. If this path is empty,
    # returns an empty path.
    def prior : UPath32
      UPath32.new(UPath32.pack(UPath32.prior(UPath32.unpack(@data))))
    end

    # Returns the last index in this path, or `nil` if this path is empty.
    def last? : UInt32?
      UPath32.last?(UPath32.unpack(@data))
    end

    # Returns the last index in this path. Raises `IndexError` if this
    # path is empty.
    def last : UInt32
      last? || raise IndexError.new
    end

    # See `Indexable#[]?(index : Int)`.
    def []?(index : Int) : UInt32?
      index += size if index < 0
      return unless 0 <= index < size

      UPath32.fetch?(UPath32.unpack(@data), index.to_u32)
    end

    # See `Indexable#[](index : Int)`.
    def [](index : Int) : UInt32
      self[index]? || raise IndexError.new
    end

    # Inserts *step* at the back of this path. Returns the modified copy.
    def append(step : UInt32) : UPath32
      UPath32.new(UPath32.pack(UPath32.append(UPath32.unpack(@data), step)))
    end

    def inspect(io)
      if end?
        io << "UPath32[End]"
        return
      end

      io << "UPath32["
      join(io, "—")
      io << "]"
    end

    # NOTE: Since we don't always normalize, the same path can be represented in
    # many different ways (e.g., `100` as IndexNonempty, Dense, or Sparse) due to
    # different histories. Thus, equal representations are only our happy path.
    # In the sad path we have to iterate-and-compare, possibly allocating some memory.

    def ==(other : UPath32) : Bool
      if @data == other.@data # cheap
        return true
      end

      unless size == other.size # cheap
        return false
      end

      # Moderately expensive.
      if UPath32.unpack(@data) == UPath32.unpack(other.@data)
        return true
      end

      # Possibly expensive.

      lhs = Kit.stack_array(UInt32, 16)
      each { |x| lhs << x }

      rhs = Kit.stack_array(UInt32, 16)
      other.each { |y| rhs << y }

      lhs == rhs
    end

    def hash(hasher)
      hasher = UPath32.hash(hasher)
      each do |step|
        hasher = step.hash(hasher)
      end
      hasher
    end
  end
end

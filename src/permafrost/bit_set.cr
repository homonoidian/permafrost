module Pf
  # An immutable set of integers backed by a fixed-width integer of type *I*.
  #
  # For `BitSet(I)`, the maximum value is `bit_width(I) - 1`. For example,
  # for `BitSet8`, you can store values `0-7`, and for `BitSet128`, `0-127`.
  #
  # *I* must be one of `UInt8`..`UInt128`. You are advised however to use
  # one of the aliases `BitSet8`..`BitSet128` instead of dealing with this
  # struct directly.
  #
  # NOTE: For consistency, most methods accept and return *I*. This may
  # require a few casts here and there on your end. A notable exception is
  # `size`: almost everything in Crystal expects its return result to be
  # an `Int32`, so we cast it on our end. For similar reasons, we do not
  # include `Enumerable` and/or `Indexable` here: its methods (such as `includes?`),
  # which are less constrained, will conflict with our policy of accepting
  # *I* only, resulting in spooky suboptimal performance (Enumerable's `includes?`
  # is O(N) where we're O(1), even though both will end up constant-time
  # in effect, the former is still slower). I know that casting can be annoying,
  # but its better to cast than to investigate an invisible performance bug!
  struct BitSet(I)
    # Returns the underlying bits.
    getter bits : I

    # Constructs a bit set from the underlying bits.
    def initialize(@bits : I)
      {% unless [UInt8, UInt16, UInt32, UInt64, UInt128].includes?(I) %}
        {% I.raise "expected one of UInt8-128" %}
      {% end %}
    end

    # Constructs an empty bit set.
    def self.empty : BitSet(I)
      new(I.new(0))
    end

    # Alias of `empty`.
    def self.[]
      empty
    end

    # Constructs a bit set with the given *values*.
    def self.[](*values : I) : BitSet(I)
      values.reduce(empty) { |set, value| set.add(value) }
    end

    # :nodoc:
    def self.bit_width(type)
      case type
      in UInt8.class   then 8
      in UInt16.class  then 16
      in UInt32.class  then 32
      in UInt64.class  then 64
      in UInt128.class then 128
      end
    end

    # Returns `true` if this set is empty.
    def empty? : Bool
      @bits.zero?
    end

    # Returns `true` if *value* exists in this set.
    def includes?(value : I) : Bool
      (@bits & (I.new(1) << value)) > 0
    end

    # Returns the number of values in this set.
    def size : Int32
      @bits.popcount.to_i
    end

    # Returns `true` if this set has no values.
    def empty? : Bool
      @bits == I.new(0)
    end

    # Returns `true` if this set has no spare capacity.
    def full? : Bool
      @bits == I::MAX
    end

    # Returns the minimum excluded value of this set.
    #
    # - Mex of an empty set is `0`
    # - Mex of a full set is the bit width of `I` (e.g. 64 for `BitSet64`). Note
    #   how the mex itself is outside of the set.
    def mex : I
      I.new((~@bits).trailing_zeros_count)
    end

    # Yields values in this set.
    def each(& : I ->) : Nil
      # Reference: https://lemire.me/blog/2018/02/21/iterating-over-set-bits-quickly/
      bitset = @bits

      loop do
        break if bitset.zero?

        t = bitset & &-bitset
        r = I.new(bitset.trailing_zeros_count)
        yield r

        bitset ^= t
      end
    end

    # Yields values in this set along with their index (`0`, `1`, `2`, etc.; do not
    # confuse with bit index).
    def each_with_index(& : I, Int32 ->) : Nil
      index = 0

      each do |value|
        yield value, index

        index += 1
      end
    end

    # Adds *value* to this set.
    def add(value : I) : BitSet(I)
      unless value < BitSet.bit_width(I)
        return self
      end

      BitSet(I).new(@bits | (I.new(1) << value))
    end

    # Removes *value* from this set.
    def delete(value : I) : BitSet(I)
      unless value < BitSet.bit_width(I)
        return self
      end

      BitSet(I).new(@bits & ~(I.new(1) << value))
    end

    # Returns a set of values less than *hi* in this set.
    def lt(hi : I) : BitSet(I)
      if hi > BitSet.bit_width(I)
        return self
      end

      mask = I::MAX >> (BitSet.bit_width(I) &- hi)

      BitSet(I).new(@bits & mask)
    end

    # Returns a set of values less than *lo* in this set.
    def gte(lo : I) : BitSet(I)
      self & lt(lo).complement
    end

    # Returns a set containing all values not in this set.
    def complement : BitSet(I)
      BitSet(I).new(~@bits)
    end

    # Returns the *rank* of value: the number of values smaller than it.
    def rank(value : I) : Int32
      lt(value).size
    end

    # Returns `true` if this and *other* sets have one or more values in common.
    def intersects?(other : BitSet(I)) : Bool
      (@bits & other.bits) > 0
    end

    # Returns `true` if all elements of this set are also elements of
    # the *other* set.
    def subset_of?(other : BitSet(I)) : Bool
      (@bits & other.bits) == @bits
    end

    # Returns `true` if all elements of this set are also elements of
    # *a larger* *other* set.
    def proper_subset_of?(other : BitSet(I)) : Bool
      size < other.size && subset_of?(other)
    end

    # Returns `true` if this set includes all elements from the *other* set.
    def superset_of?(other : BitSet(I)) : Bool
      other.subset_of?(self)
    end

    # Returns `true` if this set includes all elements from a *strictly
    # smaller* *other* set.
    def proper_superset_of?(other : BitSet(I)) : Bool
      other.proper_subset_of?(self)
    end

    # Returns the intersection of this and *other* sets.
    def &(other : BitSet(I)) : BitSet(I)
      BitSet(I).new(@bits & other.bits)
    end

    # Returns the union of this and *other* sets.
    def |(other : BitSet(I)) : BitSet(I)
      BitSet(I).new(@bits | other.bits)
    end

    # Alias of `|`.
    def +(other : BitSet(I)) : BitSet(I)
      self | other
    end

    # Returns the symmetric difference of this and *other* sets.
    def ^(other : BitSet(I)) : BitSet(I)
      BitSet(I).new(@bits ^ other.bits)
    end

    # Returns the difference of this and *other* sets.
    def -(other : BitSet(I)) : BitSet(I)
      BitSet(I).new(@bits & ~other.bits)
    end

    def inspect(io)
      io << "BitSet" << BitSet.bit_width(I) << "["

      each_with_index do |value, index|
        io << ", " if index > 0
        io << value
      end

      io << "]"
    end

    def to_s(io)
      inspect(io)
    end
  end

  alias BitSet8 = BitSet(UInt8)
  alias BitSet16 = BitSet(UInt16)
  alias BitSet32 = BitSet(UInt32)
  alias BitSet64 = BitSet(UInt64)
  alias BitSet128 = BitSet(UInt128)
end

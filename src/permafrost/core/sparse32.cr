module Pf::Core
  struct Sparse32(T)
    # Maps item count to expected capacity. '0' means 'keep' (do not grow).
    GROWTH = StaticArray(UInt8, 33).new(0u8)

    # Grow * 1.5
    GROWTH[0] = 2
    GROWTH[2] = 3
    GROWTH[3] = 5
    GROWTH[5] = 8
    GROWTH[8] = 12
    GROWTH[12] = 18
    GROWTH[18] = 27
    GROWTH[27] = 32

    # Maps population count (array size) to capacity directly.
    CAPS = StaticArray(UInt8, 33).new(0u8)

    state = GROWTH[0]
    GROWTH.each_with_index do |capacity, size|
      CAPS[size] = state = Math.max(capacity, state)
    end

    def initialize(@mem : Pointer(T), @bitmap : UInt32)
    end

    def self.new
      new(Pointer(T).malloc(GROWTH[0]), 0u32)
    end

    private def get_mask_and_offset(index)
      raise IndexError.new unless index.in?(0...32)
      mask = 1u32 << index
      {mask, (@bitmap & (mask &- 1)).popcount}
    end

    def at!(offset) : T
      @mem[offset]
    end

    # Returns the amount of elements in this array.
    def size
      @bitmap.popcount
    end

    # Yields each element from this array.
    def each(& : T ->)
      size.times { |index| yield at!(index) }
    end

    # Yields each element from this array starting from *start*, followed
    # by the element's index.
    def each(from start : Int, & : T ->)
      start.upto(size - 1) { |index| yield at!(index), index }
    end

    # Returns the element at *index*, or nil.
    #
    # *index* must be in `0...32`, otherwise `IndexError` is raised.
    def at?(index : Int) : T?
      mask, offset = get_mask_and_offset(index)

      @bitmap.bits_set?(mask) ? at!(offset) : nil
    end

    # Updates or inserts *el* at *index*.
    #
    # *index* must be in `0...32`, otherwise `IndexError` is raised.
    def put(index : Int, el : T) : self
      mask, offset = get_mask_and_offset(index)

      # If already there just replace.
      if @bitmap.bits_set?(mask)
        @mem[offset] = el
        return self
      end

      # Resize if needed.
      size = self.size
      capacity = GROWTH[size]
      mem = capacity == 0 ? @mem : @mem.realloc(capacity)

      # Shift followers by one and insert.
      (mem + offset + 1).move_from(mem + offset, size - offset)
      mem[offset] = el

      Sparse32.new(mem, @bitmap | mask)
    end

    # Removes the element at *index*. If absent this method is a noop.
    def delete(index : Int) : self
      mask, offset = get_mask_and_offset(index)

      return self unless @bitmap.bits_set?(mask)

      size = self.size

      (@mem + offset).move_from(@mem + offset + 1, size - offset - 1)
      (@mem + (size - 1)).clear

      Sparse32.new(@mem, @bitmap & ~mask)
    end

    # Returns a shallow copy of this array.
    def dup : self
      Sparse32.new(Pointer(T).malloc(CAPS[size]).copy_from(@mem, size), @bitmap)
    end

    def pretty_print(pp) : Nil
      pp.list("Sparse32{", self, "}")
    end

    def to_s(io)
      io << "Sparse32{"
      join(io, ", ")
      io << "}"
    end
  end
end

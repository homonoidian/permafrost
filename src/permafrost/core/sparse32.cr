module Pf::Core
  struct Sparse32(T)
    # Initial capacity of the array.
    INITIAL_CAPACITY = 2

    # Maps population count (array size) to grown capacity. '0' means
    # 'keep' (do not grow).
    GROWTH = StaticArray[
      # 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
      0, 0, 4, 0, 6, 0, 8, 0, 12, 0,
      # 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
      0, 0, 18, 0, 0, 0, 0, 0, 24, 0,
      # 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
      0, 0, 0, 0, 28, 0, 0, 0, 32, 0,
      # 30, 31, 32
      0, 0, 0,
    ]

    # Maps population count (array size) to capacity directly.
    CAPS = StaticArray[
      # 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
      2, 2, 4, 4, 6, 6, 8, 8, 12, 12,
      # 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
      12, 12, 18, 18, 18, 18, 18, 18, 24, 24,
      # 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
      24, 24, 24, 24, 28, 28, 28, 28, 32, 32,
      # 30, 31, 32
      32, 32, 32,
    ]

    def initialize(@mem : Pointer(T), @bitmap : UInt32)
    end

    def self.new
      new(Pointer(T).malloc(INITIAL_CAPACITY), 0u32)
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

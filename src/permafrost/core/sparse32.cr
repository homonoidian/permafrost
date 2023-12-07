module Pf::Core
  struct Sparse32(T)
    INITIAL_CAPACITY = 2

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

    # Returns the amount of elements in this array.
    def size
      @bitmap.popcount
    end

    # Yields each element from this array followed by its index.
    #
    # - *lo* can be used to specify the lower bound (the index where to start).
    def each(from lo = 0u8, & : T, UInt8 ->)
      hi = size
      while lo < hi
        yield @mem[lo], lo
        lo &+= 1
      end
    end

    # Returns the element at *index*, or nil.
    #
    # *index* must be in `0...32`, otherwise `IndexError` is raised.
    def at?(index : Int) : T?
      mask, offset = get_mask_and_offset(index)

      @bitmap.bits_set?(mask) ? @mem[offset] : nil
    end

    # Returns a copy of this array where *el* is resent at *index*.
    def with(index : Int, el : T) : Sparse32(T)
      mask, offset = get_mask_and_offset(index)
      size = self.size

      if @bitmap.bits_set?(mask)
        mem = Pointer(T).malloc(size)
        mem.copy_from(@mem, size)
        mem[offset] = el
        return Sparse32.new(mem, @bitmap)
      end

      # Copy before offset, put element at offset, copy after offset.
      mem = Pointer(T).malloc(size + 1)
      mem.copy_from(@mem, offset)
      mem[offset] = el
      (mem + offset + 1).copy_from(@mem + offset, size - offset)

      Sparse32.new(mem, @bitmap | mask)
    end

    # Returns a copy of this array where the element at *index* is absent.
    def without(index : Int) : Sparse32(T)
      mask, offset = get_mask_and_offset(index)
      return self unless @bitmap.bits_set?(mask)

      size = self.size
      mem = Pointer(T).malloc(size - 1)

      # Copy before offset, copy after offset + 1.
      mem.copy_from(@mem, offset)
      (mem + offset).copy_from(@mem + offset + 1, size - offset - 1)

      Sparse32.new(mem, @bitmap & ~mask)
    end
  end
end

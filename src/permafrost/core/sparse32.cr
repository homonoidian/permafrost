module Pf::Core
  struct Sparse32(T)
    # Returns the bitmap. The bitmap specifies which slots out of the 32 available
    # ones are occupied.
    getter bitmap : UInt32

    def initialize(@mem : T*, @bitmap : UInt32)
    end

    def self.new
      new(Pointer(T).null, 0u32)
    end

    private def get_mask_and_offset(index)
      raise IndexError.new unless index.in?(0...32)

      mask = 1u32 << index
      {mask, (@bitmap & (mask &- 1)).popcount}
    end

    # Returns a pointer to the internal buffer where `self`'s elements are stored.
    def to_unsafe : T*
      @mem
    end

    # Returns the amount of elements in this array.
    def size
      @bitmap.popcount
    end

    # Returns `true` if this array contains no elements.
    def empty? : Bool
      @bitmap.zero?
    end

    # :nodoc:
    #
    # Returns *n*-th *stored* value.
    def nth?(n : Int)
      raise IndexError.new unless n.in?(0...32)

      n < size ? @mem[n] : nil
    end

    # Yields each element from this array followed by its index.
    #
    # - *lo* can be used to specify the lower bound (the index where to start; inclusive).
    def each(from lo = 0u8, & : T, UInt8 ->)
      hi = size
      while lo < hi
        yield @mem[lo], lo
        lo &+= 1
      end
    end

    # Returns the element at *index*, or nil.
    #
    # *index* must be in `0...32`, otherwise this method raises `IndexError`.
    def at?(index : Int) : T?
      mask, offset = get_mask_and_offset(index)

      @bitmap.bits_set?(mask) ? @mem[offset] : nil
    end

    # Modifies this array at *index* by updating or inserting *el* there.
    def with!(index : Int, el : T) : self
      mask, offset = get_mask_and_offset(index)

      if @bitmap.bits_set?(mask)
        @mem[offset] = el
        return self
      end

      size = self.size

      # Grow if necessary.
      #
      # Growth-triggering sizes are powers of two. Only bother growing
      # to the next capacity if size is a power of two, then.
      if size < 32 && size & (size &- 1) == 0
        capacity = Math.pw2ceil(size + 1)
        @mem = @mem.realloc(capacity)
      end

      if offset < size
        (@mem + offset + 1).move_from(@mem + offset, size - offset)
      end

      @mem[offset] = el
      @bitmap |= mask

      self
    end

    # Modifies this array by removing the element at *index* if it was present.
    def without!(index : Int) : self
      mask, offset = get_mask_and_offset(index)
      return self unless @bitmap.bits_set?(mask)

      size = self.size

      (@mem + offset).move_from(@mem + offset + 1, size - offset - 1)
      (@mem + (size - 1)).clear

      @bitmap &= ~mask

      self
    end

    # Returns a copy of this array where *el* is present at *index*.
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

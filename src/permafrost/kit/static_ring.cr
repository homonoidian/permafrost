module Pf::Kit
  struct StaticRing(T, N)
    def initialize
      @bot = 0u32
      @size = 0u32

      @ring = uninitialized T[N]
    end

    private def slot_index : UInt32
      (@bot &+ @size) % N
    end

    private def top_index : UInt32
      (@bot &+ @size &- 1) % N
    end

    def top? : T?
      return if @size.zero?

      unsafe_top
    end

    def unsafe_top : T
      @ring.unsafe_fetch(top_index)
    end

    def unsafe_set(object : T)
      @ring.unsafe_put(top_index, object)
    end

    def each(& : T ->)
      @size.times { |index| yield @ring.unsafe_fetch(index) }
    end

    def size : Int32
      @size.to_i
    end

    def unsafe_fetch(index : Int)
      @ring.unsafe_fetch(index)
    end

    def unsafe_put(index : Int, object : T)
      @ring.unsafe_put(index, object)
    end

    def push(object : T, & : T ->) : Nil
      if @size < N
        @ring.unsafe_put(slot_index, object)
        @size += 1
      else
        yield @ring[@bot]
        @bot = (@bot + 1) % N # evict bottom
        @ring.unsafe_put(top_index, object)
      end
    end

    def pop? : T?
      return if @size.zero?

      object = @ring.unsafe_fetch(top_index)
      @size -= 1
      object
    end

    def unsafe_fill(src : T*, count : UInt32) : Nil
      @bot = 0u32
      @size = count

      src.copy_to(@ring.to_unsafe, count)
    end

    def clear : Nil
      @bot = @size = 0u32
    end
  end
end

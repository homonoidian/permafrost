module Pf::Kit
  # A dynamic array which stores *N* x *T*s in a fixed-size buffer (inline; most
  # often allocated on the stack), and spills over to heap.
  #
  # Inspiration: One of Walter Bright talks, at https://www.youtube.com/watch?v=_PB6Hdi4R7M&t=2606s
  #
  # `HybridArray` is a reference type to limit hazardous usage by default. Note
  # that it is a hazardous type anyway, so you're probably better off using a normal
  # `Array`, unless you're working on the moderate to deep sub-microsecond time-scale.
  #
  # The sub-microsecond time-scale starts to require things like these the lower
  # you go. Consider HybridArray that odd-looking fish living at the bottom of
  # the Mariana Trench, hyper-optimized for its particular niche but otherwise
  # an abomination.
  #
  # If you are using a HybridArray with a stack-allocated buffer, it makes little
  # sense to not stack-allocate the HybridArray itself as well.
  #
  # You can use the `Pf::Kit.stack_array` macro to allocate a hybrid array
  # and its buffer on the stack. See it for more info.
  class HybridArray(T, N)
    include Indexable::Mutable(T)

    # :nodoc:
    INITIAL_SPILL_CAPACITY = 8u32

    # @type_id : Int32
    @bufsize : UInt32

    @buffer : T*
    @spill : T*

    @spillcap : UInt32
    @spillsize : UInt32

    # WARNING: There are no checks making sure `N` = *buffer* size (in fact, *buffer*
    # has no known size or "size" at all at this point!)
    def initialize(@buffer : T*)
      {% if N == 0 %}
        {% N.raise "HybridArray with N=0 makes no sense, use Array" %}
      {% end %}

      @bufsize = 0u32

      @spill = Pointer(T).null
      @spillcap = 0u32
      @spillsize = 0u32
    end

    # Returns the underlying `UInt32` size of this array.
    #
    # `size` simply converts it to `Int32`, which is what Crystal's standard
    # library expects.
    def usize : UInt32
      @bufsize + @spillsize
    end

    def size : Int32
      usize.to_i
    end

    def unsafe_fetch(index : Int) : T
      if index < @bufsize
        return @buffer[index]
      end

      @spill[index - @bufsize]
    end

    def unsafe_put(index : Int, value : T) : Nil
      if index < @bufsize
        @buffer[index] = value
        return
      end

      @spill[index - @bufsize] = value
    end

    # Inserts *value* at the back of this array.
    def push(value : T) : self
      if @bufsize + 1 <= N
        @buffer[@bufsize] = value
        @bufsize += 1
        return self
      end

      reserve(size + 1)

      @spill[@spillsize] = value
      @spillsize += 1

      self
    end

    # :ditto:
    def <<(value : T) : self
      push(value)
    end

    # Increases the capacity of this array to a value greater than or equal
    # to *newsize*.
    #
    # This applies to the spill part. If *newsize* is less than N, the inline
    # part's capacity, this function does nothing. Ditto if the spill part's capacity
    # is greater than or equal to *capacity*.
    def reserve(newsize : Int32 | UInt32) : self
      newsize = newsize.to_u32
      return self if newsize <= N

      newsize -= N
      return self if newsize <= @spillcap

      @spillcap = Math.max(Math.max(INITIAL_SPILL_CAPACITY, newsize), @spillcap + @spillcap//2) # 1.5x
      @spill = @spill.realloc(@spillcap)

      self
    end

    # Pushes all elements in *other* to this array.
    def concat(other : Indexable(T)) : self
      reserve(size + other.size)

      other.each { |object| push(object) }

      self
    end

    # Removes and returns the last value of this array. Returns `nil` if
    # this array is empty.
    def pop? : T?
      return unless @bufsize > 0

      if @spillsize > 0
        @spillsize -= 1
        value = @spill[@spillsize]
        (@spill + @spillsize).clear
        return value
      end

      @bufsize -= 1

      # There is no point in clearing the buffer since it's stack-allocated and
      # will be cleared anyway.
      @buffer[@bufsize]
    end

    # Removes and returns the last value of this array. Raises `IndexError` if
    # this array is empty.
    def pop : T
      pop? || raise IndexError.new
    end

    # Removes all values from this array.
    def clear : Nil
      @spill.clear(@spillsize)
      @spillsize = 0u32

      # There is no point in clearing the buffer since it's stack-allocated and
      # will be cleared anyway.
      @bufsize = 0u32
    end

    # WARNING: the destination must not overlap with this array's buffer (uses `Pointer#copy_to`).
    # WARNING: no checks are done with respect to the size of *target*.
    def unsafe_copy_to(target : T*) : Nil
      @buffer.copy_to(target, @bufsize)
      if @spillsize > 0
        @spill.copy_to(target + @bufsize, @spillsize)
      end
    end

    # Returns a copy of this array's content as a slice.
    def to_slice : Slice(T)
      target = Pointer(T).malloc(size)
      unsafe_copy_to(target)

      Slice.new(target, size)
    end

    # Returns a copy of this array's content as a read-only slice.
    def to_readonly_slice : Slice(T)
      slice = to_slice

      Slice.new(slice.to_unsafe, slice.size, read_only: true)
    end

    # Returns a slice referencing the content of this array.
    #
    # This overload is most beneficial when there is spillover. When there is none,
    # this overload is the same as calling `to_slice`.
    #
    # Since spillover reserves 1.5x more memory than strictly necessary, we can
    # use that extra memory, when possible, to memmove, and then put the array's
    # inline (e.g. stack-allocated) content in front. This overload does exactly that.
    #
    # If we can't use the remaining memory (inline content doesn't fit in spillover),
    # we *reallocate*, which means the GC may give us the same chunk of memory,
    # but longer. Sometimes it will not.
    #
    # WARNING: This method alters this array's original content. You **must not**
    # use the array after calling this method, as its spillover part is now referenced
    # by others.
    def to_unsafe_slice! : Slice(T)
      if @spillsize.zero?
        return to_readonly_slice
      end

      unless @bufsize + @spillsize <= @spillcap
        @spillcap = @bufsize + @spillsize
        @spill = @spill.realloc(@spillcap)
      end

      @spill.move_to(@spill + @bufsize, @spillsize)
      @spill.copy_from(@buffer, @bufsize)
      @spillsize += @bufsize

      # Reclaim memory, if possible.
      if @spillsize < @spillcap
        @spillcap = @spillsize
        @spill = @spill.realloc(@spillcap)
      end

      Slice.new(@spill, @spillsize)
    end

    # Returns a slice referencing the content of this array.
    #
    # See `to_unsafe_slice!` for info on safety.
    def to_unsafe_readonly_slice! : Slice(T)
      slice = to_unsafe_slice!

      Slice.new(slice.to_unsafe, slice.size, read_only: true)
    end

    def inspect(io)
      to_s(io)
    end

    def to_s(io : IO) : Nil
      io << "HybridArray{"
      join(io, ", ", &.inspect(io))
      io << '}'
    end

    def pretty_print(pp) : Nil
      pp.list("HybridArray{", self, "}")
    end

    def ==(other : HybridArray(T, N)) : Bool
      equals?(other) { |a, b| a == b }
    end
  end
end

module Pf::Kit
  # A dynamic array that stores *N* x *T*s in a fixed-size buffer (most
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
    INITIAL_SPILL_CAPACITY = 8

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
      if @bufsize < N
        @buffer[@bufsize] = value
        @bufsize += 1
        return self
      end

      unless @spillsize < @spillcap
        @spillcap = Math.max(INITIAL_SPILL_CAPACITY, @spillcap * 1.5).to_u32
        @spill = @spill.realloc(@spillcap)
      end

      @spill[@spillsize] = value
      @spillsize += 1

      self
    end

    # :ditto:
    def <<(value : T) : self
      push(value)
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
      value = @buffer[@bufsize]
      (@buffer + @bufsize).clear
      value
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

      @buffer.clear(@bufsize)
      @bufsize = 0u32
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

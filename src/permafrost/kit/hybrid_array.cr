module Pf::Kit
  # A hybrid array stores *N* x *T*s on the stack and spills over to heap.
  #
  # NOTE: This is a struct. You can assign it to a local variable or an instance
  # variable and use it safely. When passing it to functions, however, be careful.
  # First of all, naked HybridArrays are expected to be "huge structs" -- hundreds
  # to thousands of bytes. Besides, if you pass a naked HybridArray, the callee
  # will receive a copy -- not nice, most of the times. So prefer to use `pointerof(var)`
  # or `pointerof(@ivar)`, but *please* be aware of their caveats (and unsafety!)
  #
  # Inspiration: One of Walter Bright talks, at https://www.youtube.com/watch?v=_PB6Hdi4R7M&t=2606s
  struct HybridArray(T, N)
    include Indexable::Mutable(T)

    # :nodoc:
    INITIAL_SPILL_CAPACITY = 8

    def initialize
      {% if N == 0 %}
        {% N.raise "HybridArray with N=0 makes no sense, use Array" %}
      {% end %}

      @spill = Pointer(T).null
      @spillcap = 0u32
      @spillsize = 0u32

      @size = 0u32
      @data = uninitialized T[N]
    end

    # Returns the underlying `UInt32` size of this array.
    #
    # `size` simply converts it to `Int32`, which is what Crystal's standard
    # library expects.
    def usize : UInt32
      @size + @spillsize
    end

    def size : Int32
      usize.to_i
    end

    def unsafe_fetch(index : Int) : T
      if index < @size
        return @data.unsafe_fetch(index)
      end

      @spill[index - @size]
    end

    def unsafe_put(index : Int, value : T) : Nil
      if index < @size
        return @data.unsafe_put(index, value)
      end

      @spill[index - @size] = value
    end

    # Inserts *value* at the back of this array.
    def push(value : T) : Nil
      if @size < N
        @data.unsafe_put(@size, value)
        @size += 1
        return
      end

      unless @spillsize < @spillcap
        @spillcap = Math.max(INITIAL_SPILL_CAPACITY, @spillcap * 1.5).to_u32
        @spill = @spill.realloc(@spillcap)
      end

      @spill[@spillsize] = value
      @spillsize += 1
    end

    # :ditto:
    #
    # NOTE: Normally, in Crystal, `<<` (and `push`) return `self`; but for
    # `HybridArray` this would be malicious, since it's stored largely
    # on the stack.
    def <<(value : T) : Nil
      push(value)
    end

    # Removes and returns the last value of this array. Returns `nil` if
    # this array is empty.
    def pop? : T?
      return unless @size > 0

      if @spillsize > 0
        @spillsize -= 1
        value = @spill[@spillsize]
        (@spill + @spillsize).clear
        return value
      end

      @size -= 1
      value = @data[@size]
      (@data.to_unsafe + @size).clear
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

      @data.to_unsafe.clear(@size)
      @size = 0u32
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
  end
end

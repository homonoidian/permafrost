module Pf::Kit
  struct HybridArray(T, N)
    include Indexable::Mutable(T)

    INITIAL_SPILL_CAPACITY = 8

    def initialize
      {% if N == 0 %}
        {% N.raise "HybridArray with N=0 makes no sense, use Array" %}
      {% end %}

      @spill = Pointer(T).null

      @spillcap = 0u32
      @spillsize = 0u32

      @ring = StaticRing(T, N).new
    end

    def size : Int32
      (@spillsize.to_i + @ring.size)
    end

    def unsafe_fetch(index : Int) : T
      if index < @spillsize
        return @spill[index]
      end

      @ring.unsafe_fetch(index &- @spillsize)
    end

    def unsafe_put(index : Int, value : T) : Nil
      if index < @spillsize
        @spill[index] = value
        return
      end

      @ring.unsafe_put(index &- @spillsize, value)
    end

    # Provides fast access to the top of the stack.
    def top? : T?
      @ring.top?
    end

    def unsafe_top : T
      @ring.unsafe_top
    end

    def unsafe_set(object : T)
      @ring.unsafe_set(object)
    end

    def each(& : T ->)
      @spillsize.times do |index|
        yield @spill[index]
      end

      @ring.each do |object|
        yield object
      end
    end

    def push(object : T) : Nil
      @ring.push(object) do |front|
        if (@spillsize &+ 1) > @spillcap
          if @spillcap.zero?
            @spillcap = INITIAL_SPILL_CAPACITY
          else
            @spillcap = (@spillcap * 1.5).to_u32!
          end

          @spill = @spill.realloc(@spillcap)
        end

        @spill[@spillsize] = front
        @spillsize &+= 1
      end
    end

    def <<(object : T) : Nil
      push(object)
    end

    def pop? : T?
      if object = @ring.pop?
        return object
      end

      return if @spillsize.zero?

      if @spillsize < N
        @ring.unsafe_fill(@spill, @spillsize)
        @spillsize = 0u32
      else
        @ring.unsafe_fill(@spill + (@spillsize &- N), N.to_u32)
        @spillsize &-= N
      end

      @ring.pop?
    end

    def pop
      pop? || raise IndexError.new
    end

    def clear : Nil
      @ring.clear
      @spill.clear(@spillsize)
      @spillsize = 0u32
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

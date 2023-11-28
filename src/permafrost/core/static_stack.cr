module Pf::Core
  struct StaticStack(T, N)
    include Enumerable(T)

    getter size

    def initialize
      @stack = uninitialized T[N]
      @size = 0u8
    end

    def each(& : T ->)
      @size.times { |index| yield @stack[index] }
    end

    def push(element : T)
      @stack[@size] = element
      @size += 1
    end

    def pop?
      @size.zero? ? nil : @stack[@size -= 1]
    end

    def pop : T
      @stack[@size -= 1]
    end
  end
end

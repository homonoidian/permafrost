# Includers are `Pf::Map` value types whose `#==` method can be used
# to determine whether two values are equal after reassignment. This
# helps to avoid path copying if the values do indeed turn out equal.
module Pf::Eq
end

module Pf::Core
  abstract class Node(K, V)
    # Window size over a 32-bit path to the mapping.
    PROGRESS_STEP = 5

    # Returns the 32 bit hash of *object*.
    macro hash32(object)
      {{object}}.hash.unsafe_as(UInt32)
    end

    # Returns `0...32` index based on a 32-bit *path* and a *progress* offset
    # into that path. *progress* should be a multiple of `PROGRESS_STEP`.
    macro index32(path, progress)
      (({{path}}) >> ({{progress}})) & 0x1f
    end

    # Returns if two mapping values *v1* and *v2* are equal.
    def self.eqv?(v1 : V, v2 : V) : Bool
      {% if V < ::Pf::Eq || V == ::Nil || V == ::Bool || V == ::Char || V == ::String || V == ::Symbol || V < ::Number::Primitive %}
        v1 == v2
      {% elsif V < ::Reference %}
        v1.same?(v2)
      {% else %}
        false
      {% end %}
    end

    # Returns the amount of mappings in this node.
    abstract def size : Int32

    # Yields each mapping starting from `self`.
    abstract def each(& : K, V ->) : Nil

    # Tries to find which value *needle* key is mapped to starting from `self`.
    abstract def find?(needle : K) : Cloak(V)?

    # :nodoc:
    abstract def assoc(mapping : Mapping(K, V), path : UInt32, progress : UInt32) : Node(K, V)

    # Inserts or replaces `self` with the given *mapping*. Returns the
    # new version of `self`.
    def assoc(mapping : Mapping(K, V)) : Node(K, V)
      assoc(mapping, path: hash32(mapping.kv[0]), progress: 0)
    end

    # :nodoc:
    abstract def dissoc(needle : K, path : UInt32, progress : UInt32) : Node(K, V)

    # Removes the mapping of *needle*, if any.
    def dissoc(needle : K) : Node(K, V)
      dissoc(needle, path: hash32(needle), progress: 0)
    end
  end

  # No mappings. Returned (a) when creating a new map or (b) when all
  # mappings were removed from a map.
  class Node::Empty(K, V) < Node(K, V)
    def size : Int32
      0
    end

    def each(& : K, V ->) : Nil
    end

    def find?(needle : K) : Cloak(V)?
    end

    def assoc(mapping : Mapping(K, V), path : UInt32, progress : UInt32) : Node(K, V)
      mapping
    end

    def dissoc(needle : K, path : UInt32, progress : UInt32) : Node(K, V)
      self
    end
  end

  # A single mapping. Returned when a map has only one entry.
  class Node::Mapping(K, V) < Node(K, V)
    def initialize(@key : K, @value : V)
    end

    # Returns the key and the value of this mapping.
    def kv : {K, V}
      {@key, @value}
    end

    def size : Int32
      1
    end

    def each(& : K, V ->) : Nil
      yield @key, @value
    end

    def find?(needle : K) : Cloak(V)?
      @key == needle ? Cloak.new(@value) : nil
    end

    def assoc(mapping : Mapping(K, V), path : UInt32, progress : UInt32) : Node(K, V)
      here = hash32(@key)

      index0 = index32(here, progress)
      index1 = index32(path, progress)

      # If indices are *not* equal we can assoc faster.
      unless index0 == index1
        return Row(K, V).new.assoc!(self, index0).assoc!(mapping, index1)
      end

      # If indices are the same but paths are different we have to insert
      # smart. We can't just skip parts of the path so this will possibly
      # create nested Rows.
      unless here == path
        return Row(K, V).new.assoc(self, here, progress).assoc(mapping, path, progress)
      end

      key, value = mapping.kv

      # If paths are equal but keys are not, that's a collision. We must
      # insulate Collision in a row because otherwise, Collision will accept
      # all incoming mappings and that's the least cool thing ever.
      unless @key == key
        return Row(K, V).new.assoc!(Collision.new([self, mapping]), index0)
      end

      Node.eqv?(@value, value) ? self : mapping
    end

    def dissoc(needle : K, path : UInt32, progress : UInt32) : Node(K, V)
      here = hash32(@key)

      return self unless here == path
      return self unless needle == @key

      Empty(K, V).new
    end
  end

  class Node::Row(K, V) < Node(K, V)
    getter size : Int32

    def initialize(@cols : Sparse32(Node(K, V)) = Sparse32(Node(K, V)).new, @size = 0)
    end

    # See `Sparse32`.
    delegate :at!, :at?, to: @cols

    # Returns the amount of columns.
    def ncols
      @cols.size
    end

    # Unsafe, mutable assoc. Assumes `self` is empty, does no copies, and
    # skips all checks.
    def assoc!(node : Node(K, V), index : UInt32) : Node(K, V)
      @cols = @cols.put(index, node)
      @size += node.size
      self
    end

    def each(&block : K, V ->) : Nil
      current = 0u8

      states = uninitialized {Row(K, V), UInt32}[7]
      states[current] = {self, 0u32}

      while true
        continue = false

        node, start = states[current]

        start.upto(node.ncols - 1) do |index|
          col = node.at!(index)
          if col.is_a?(Mapping) || col.is_a?(Collision)
            col.each { |k, v| yield k, v }
            next
          end

          next unless col.is_a?(self)

          states[current] = {node, index + 1} # Save current state
          states[current += 1] = {col, 0u32}  # Push new state
          continue = true

          break
        end

        next if continue
        break if current.zero?

        current -= 1 # Pop state
      end
    end

    def find?(needle : K) : Cloak(V)?
      node = self
      path = hash32(needle)
      7.times do
        return unless newnode = node.at?(path & 0x1f)
        return newnode.find?(needle) unless newnode.is_a?(Row)
        node = newnode
        path >>= PROGRESS_STEP
      end
    end

    def assoc(mapping : Mapping(K, V), path : UInt32, progress : UInt32) : Node(K, V)
      index = index32(path, progress)
      unless col = @cols.at?(index)
        return Row.new(@cols.dup.put(index, mapping), @size + 1)
      end

      newcol = col.assoc(mapping, path, progress + PROGRESS_STEP)
      return self if col.same?(newcol)

      Row.new(@cols.dup.put(index, newcol), @size + (newcol.size - col.size))
    end

    def dissoc(needle : K, path : UInt32, progress : UInt32) : Node(K, V)
      index = index32(path, progress)
      return self unless col = @cols.at?(index)

      newcol = col.dissoc(needle, path, progress + PROGRESS_STEP)
      return self if col.same?(newcol)

      delta = newcol.size - col.size
      if newcol.size.zero?
        return Empty(K, V).new if @cols.size == 1 # Will remove the last one

        Row.new(@cols.dup.delete(index), @size + delta)
      else
        Row.new(@cols.dup.put(index, newcol), @size + delta)
      end
    end
  end

  # Represents a collision between several mappings. A collision occurs
  # when hashes of two keys (`hash`) are the same but the actual keys
  # compare differently (`==`).
  #
  # This situation is generally rare, therefore, this node is kept
  # simple & unoptimized (`Array#dup`s etc.).
  class Node::Collision(K, V) < Node(K, V)
    def initialize(@mappings = [] of Mapping(K, V))
    end

    def size : Int32
      @mappings.size
    end

    def each(& : K, V ->) : Nil
      @mappings.each { |mapping| yield *mapping.kv }
    end

    def find?(needle : K) : Cloak(V)?
      each { |key, value| return Cloak.new(value) if needle == key }
    end

    def assoc(mapping : Mapping(K, V), path : UInt32, progress : UInt32) : Node(K, V)
      key, value = mapping.kv

      @mappings.each_with_index do |other, index|
        k, v = other.kv
        if key == k
          return self if Node.eqv?(value, v)
          copy = @mappings.dup
          copy.swap(0, index) # Lift due to usage
          copy[0] = mapping
          return Collision.new(copy)
        end
      end

      copy = @mappings.dup
      copy.unshift(mapping)

      Collision.new(copy)
    end

    def dissoc(needle : K, path : UInt32, progress : UInt32) : Node(K, V)
      @mappings.each_with_index do |mapping, index|
        k, v = mapping.kv
        if needle == k
          return Empty(K, V).new if @mappings.empty?
          copy = @mappings.dup
          copy.delete_at(index)
          return Collision.new(copy)
        end
      end

      self
    end
  end
end

module Pf
  # A thread-safe, persistent, unordered set.
  #
  # See also: `Map`.
  struct Set(T)
    include Enumerable(T)

    protected def initialize(@map : Map(T, Nil))
    end

    def self.additive_identity : self
      Set(T).new
    end

    # Returns a new, empty set.
    #
    # ```
    # set = Pf::Set(Int32).new
    # set.empty? => true
    # ```
    def self.new : Set(T)
      new(Map(T, Nil).new)
    end

    # Returns a new set with the elements from *enumerable*.
    #
    # ```
    # set = Pf::Set.new([1, 2, 3])
    # set # => Pf::Set[1, 2, 3]
    # ```
    def self.new(enumerable : Enumerable(T)) : Set(T)
      enumerable.reduce(Set(T).new) { |set, element| set.add(element) }
    end

    # Returns a new set with the given *elements*.
    #
    # The type of the returned set is the union of the types of *elements*.
    #
    # ```
    # set = Pf::Set[1, "Hello", 3, true]
    # set # => Pf::Set[1, "Hello", 3, true]
    #
    # typeof(set) # => Pf::Set(String | Int32 | Bool)
    # ```
    def self.[](*elements)
      elements.reduce(Set(typeof(Enumerable.element_type(elements))).new) do |set, element|
        set.add(element.as(typeof(Enumerable.element_type(elements))))
      end
    end

    # Returns the number of elements in this set.
    #
    # ```
    # set = Pf::Set[1, 5]
    # set.size # => 2
    # ```
    def size : Int32
      @map.size
    end

    # Returns `true` if this set is empty.
    #
    # ```
    # set = Pf::Set(Int32).new
    # set.empty? # => true
    #
    # newset = set.add(100)
    # newset.empty? # => false
    # ```
    def empty? : Bool
      @map.empty?
    end

    # Returns `true` if *element* is present in this set.
    #
    # ```
    # set = Pf::Set[1, 2, 3]
    #
    # 1.in?(set)        # => true
    # 2.in?(set)        # => true
    # 3.in?(set)        # => true
    # 100.in?(set)      # => false
    # "foobar".in?(set) # => false
    # ```
    def includes?(element : T) : Bool
      @map.includes?(element)
    end

    # :nodoc:
    def includes?(element) : Bool
      false
    end

    # Yields each element from this set.
    def each(& : T ->) : Nil
      @map.each_key { |element| yield element }
    end

    # Yields each element from this set to the block and constructs
    # a new set from block return results.
    #
    # Supports value equality if `T == U`.
    #
    # ```
    # set = Pf::Set[1, 2, 3]
    # set.fmap(&.succ.to_s) # => Pf::Set["2", "3", "4"]
    # ```
    def fmap(& : T -> U) : Set(U) forall U
      Set.new(@map.map_key { |element| yield element })
    end

    # Returns a new set that includes only elements for which the
    # block is *truthy*.
    #
    # *Supports value equality*.
    #
    # ```
    # set = (0...10).to_pf_set
    # set.select(&.even?) # => Pf::Set[0, 2, 4, 6, 8]
    # ```
    def select(& : T ->) : Set(T)
      Set.new(@map.select { |element, _| yield element })
    end

    # Returns a new set that includes only elements for which the
    # block is *falsey*.
    #
    # *Supports value equality*.
    #
    # ```
    # set = (0...10).to_pf_set
    # set.reject(&.even?) # => Pf::Set[1, 3, 5, 7, 9]
    # ```
    def reject(& : T ->) : Set(T)
      Set.new(@map.reject { |element, _| yield element })
    end

    # Returns a new set containing elements common to this and *other* sets.
    #
    # ```
    # a = Pf::Set[1, 2, 3]
    # b = Pf::Set[4, 5, 1, 6, 2]
    # a & b # => Pf::Set[1, 2]
    # ```
    def &(other : Set(T))
      smallest, largest = size < other.size ? {self, other} : {other, self}
      smallest.select { |element| element.in?(largest) }
    end

    # Returns a copy of this set that includes *element*.
    #
    # *Supports value equality*.
    #
    # ```
    # set = Pf::Set[100, 200]
    # set.add(300) # => Pf::Set[100, 200, 300]
    # set.add(400) # => Pf::Set[100, 200, 400]
    # ```
    def add(element : T) : Set(T)
      Set.new(@map.assoc(element, nil))
    end

    # Returns a copy of this set that is guaranteed not to include
    # *element*.
    #
    # ```
    # set = Pf::Set[100, 200, 300]
    # set.delete(100) # => Pf::Set[200, 300]
    # set.delete(200) # => Pf::Set[100, 300]
    # ```
    def delete(element : T) : Set(T)
      Set.new(@map.dissoc(element))
    end

    # Returns a copy of this set that also includes elements from
    # *other* enumerable.
    #
    # *Supports value equality*.
    #
    # ```
    # a = Pf::Set[1, 2, 3]
    # a.concat([4, 5, 1, 2]) # => Pf::Set[1, 2, 3, 4, 5]
    # ```
    def concat(other : Enumerable(T)) : Set(T)
      Set.new(@map.merge(other.@map))
    end

    # Shorthand for `concat`.
    def +(other) : Set(T)
      concat(other)
    end

    # :nodoc:
    delegate :object_id, to: @map

    # Returns `true` if `self` and *other* refer to the same set in memory.
    #
    # Due to the way `Set` is implemented, this method can be used as
    # a cheap way to detect changes.
    #
    # ```
    # set1 = Pf::Set[1, 2, 3]
    # set2 = set1.add(1).add(2).add(3)
    # set1.same?(set2) # => true
    # ```
    def same?(other : Set(T))
      @map.same?(other.@map)
    end

    # Same as `Set#===`.
    #
    # ```
    # reds = Pf::Set["red", "pink", "violet"]
    # blues = Pf::Set["blue", "azure", "violet"]
    #
    # both = red = blue = false
    #
    # case "violet"
    # when reds & blues
    #   both = true
    # when reds
    #   red = true
    # when blues
    #   blue = true
    # end
    #
    # both # => true
    # red  # => false
    # blue # => false
    # ```
    def ===(object : T) : Bool
      includes?(object)
    end

    # Alias of `#to_s`.
    def inspect(io : IO) : Nil
      to_s(io)
    end

    def to_s(io)
      io << "Pf::Set["
      join(io, ", ")
      io << "]"
    end

    def pretty_print(pp) : Nil
      pp.list("Pf::Set[", self, "]")
    end

    # Returns `true` if two sets are equal.
    def_equals @map

    # See `Object#hash(hasher)`.
    def hash(hasher)
      result = hasher.result

      copy = hasher
      copy = self.class.hash(copy)
      result &+= copy.result

      copy = hasher
      copy = @map.hash(copy)
      result &+= copy.result

      result.hash(hasher)
    end
  end
end

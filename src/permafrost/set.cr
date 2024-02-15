module Pf
  # A thread-safe, persistent, unordered set.
  #
  # See also: `Map`.
  struct Set(T)
    include Core
    include Enumerable(T)

    module Probe
      struct Includes(T)
        include IProbeFetch(T)

        def initialize(@value : T)
        end

        def path : UInt64
          Core.hash64(@value)
        end

        def match?(stored : T) : Bool
          @value == stored
        end
      end

      struct Add(T)
        include IProbeAdd(T)

        getter value : T

        def initialize(@value : T)
        end

        def path : UInt64
          Core.hash64(@value)
        end

        def match?(stored) : Bool
          @value == stored
        end

        def author : AuthorId
          AUTHOR_NONE
        end

        def replace?(stored) : Bool
          false
        end
      end

      struct MutAdd(T)
        include IProbeAdd(T)

        getter value : T
        getter author : AuthorId

        def initialize(@value, @author)
        end

        def path : UInt64
          Core.hash64(@value)
        end

        def match?(stored) : Bool
          @value == stored
        end

        def replace?(stored) : Bool
          false
        end
      end

      struct Delete(T)
        include IProbeDelete(T)

        getter value : T

        def initialize(@value : T)
        end

        def path : UInt64
          Core.hash64(@value)
        end

        def match?(stored : T) : Bool
          @value == stored
        end

        def author : AuthorId
          AUTHOR_NONE
        end
      end

      struct MutDelete(T)
        include IProbeDelete(T)

        getter value : T
        getter author : AuthorId

        def initialize(@value, @author)
        end

        def path : UInt64
          Core.hash64(@value)
        end

        def match?(stored : T) : Bool
          @value == stored
        end
      end
    end

    class Commit(T)
      @@id : Atomic(UInt64) = Atomic.new(AUTHOR_FIRST)

      def self.genid
        @@id.add(1)
      end

      protected def initialize(@set : Set(T), @fiber : UInt64)
        @id = AuthorId.new(Commit.genid)
        @resolved = false
      end

      delegate :includes?, to: @set

      def add(element : T)
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == fiber_id

        @set = @set.add!(element, @id)

        self
      end

      def delete(element : T)
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == fiber_id

        @set = @set.delete!(element, @id)

        self
      end

      def resolve
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == fiber_id

        @resolved = true
        @set
      end
    end

    # Returns the number of elements in this set.
    #
    # ```
    # set = Pf::Set[1, 5]
    # set.size # => 2
    # ```
    getter size : Int32

    protected def initialize(@node : Node(T), @size = 0)
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
      new(node: Node(T).new, size: 0)
    end

    # Returns a new set containing elements from *enumerable*.
    #
    # ```
    # set = Pf::Set.new([1, 2, 3])
    # set # => Pf::Set[1, 2, 3]
    # ```
    def self.new(enumerable : Enumerable(T)) : Set(T)
      Set(T).new.concat(enumerable)
    end

    def self.transaction(& : Commit(T) -> Commit(T)) : Set(T)
      new.transaction { |commit| yield commit }
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
      Set(typeof(Enumerable.element_type(elements))).new.concat(elements)
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
      @size.zero?
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
      !!@node.fetch?(Probe::Includes.new(element))
    end

    # :nodoc:
    def includes?(element) : Bool
      false
    end

    # Yields each element from this set.
    def each(& : T ->) : Nil
      @node.each { |element| yield element }
    end

    def transaction(& : Commit(T) ->) : Set(T)
      commit = Commit.new(self, fiber_id)
      yield commit
      commit.resolve
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
      {% if T == U %}
        same = true
        set = Set(U).transaction do |commit|
          each do |element|
            newelement = yield element
            commit.add(newelement)
            next if newelement.in?(self)
            same = false
          end
          commit
        end
        same ? self : set
      {% else %}
        Set(U).transaction do |commit|
          each do |element|
            commit.add(yield element)
          end
          commit
        end
      {% end %}
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
      transaction do |commit|
        each do |element|
          next if yield element
          commit.delete(element)
        end
        commit
      end
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
      self.select { |element| !(yield element) }
    end

    # Returns a new set containing elements common to this and *other* sets.
    #
    # ```
    # a = Pf::Set[1, 2, 3]
    # b = Pf::Set[4, 5, 1, 6, 2]
    # a & b # => Pf::Set[1, 2]
    # ```
    def &(other : Set(T))
      smaller, larger = size <= other.size ? {self, other} : {other, self}
      smaller.select { |element| element.in?(larger) }
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
      added, node = @node.add(Probe::Add.new(element))
      added ? Set.new(node, @size + 1) : self
    end

    protected def add!(element : T, author : AuthorId)
      added, node = @node.add(Probe::MutAdd.new(element, author))
      added ? Set.new(node, @size + 1) : self
    end

    # Returns a copy of this set that is guaranteed not to include
    # *element*.
    #
    # *Supports value equality*.
    #
    # ```
    # set = Pf::Set[100, 200, 300]
    # set.delete(100) # => Pf::Set[200, 300]
    # set.delete(200) # => Pf::Set[100, 300]
    # ```
    def delete(element : T) : Set(T)
      removed, node = @node.delete(Probe::Delete.new(element))
      removed ? Set.new(node, @size - 1) : self
    end

    protected def delete!(element : T, author : AuthorId) : Set(T)
      removed, node = @node.delete(Probe::MutDelete.new(element, author))
      removed ? Set.new(node, @size - 1) : self
    end

    # :nodoc:
    def concat(other : Pf::Set(T)) : Set(T)
      return self if other.empty?

      smaller, larger = size < other.size ? {self, other} : {other, self}
      larger.transaction do |commit|
        smaller.each do |element|
          commit.add(element)
        end
        commit
      end
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
      transaction do |commit|
        other.each do |element|
          commit.add(element)
        end
        commit
      end
    end

    # Shorthand for `concat`.
    def +(other) : Set(T)
      concat(other)
    end

    # :nodoc:
    delegate :object_id, to: @node

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
      @node.same?(other.@node)
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

    # Returns `true` if the sets are equal.
    def ==(other : Set)
      return true if same?(other)
      return false unless @size == other.size

      all? &.in?(other)
    end

    # :nodoc:
    def ==(other)
      false
    end

    # See `Object#hash(hasher)`.
    def hash(hasher)
      result = hasher.result

      copy = hasher
      copy = self.class.hash(copy)
      result &+= copy.result

      each do |element|
        copy = hasher
        copy = element.hash(copy)
        result &+= copy.result
      end

      result.hash(hasher)
    end
  end
end

module Pf
  # Includers are `Pf::Map` value types whose `#==` method can be used
  # to determine whether two values are equal after reassignment. This
  # helps to avoid path copying if the values do indeed turn out equal.
  module Eq
  end

  # A thread-safe, persistent, unordered hash map.
  #
  # ## Value equality
  #
  # Being a persistent map, `Pf::Map` tries to avoid path copying. This
  # is done by comparing the old and new values using `==`. In particular,
  # methods that *support value equality* do so.
  #
  # Note that, out of the box, `==` is called only when your value is
  # of the types `nil`, `Bool`, `Char`, `String`, `Symbol`, or of a
  # primitive number type.
  #
  # `same?` is called on all reference (`Reference`) types.
  #
  # ```
  # map = Pf::Map[foo: 100, bar: 200]
  # map.assoc("foo", 100).same?(map)             # => true, no change
  # map.update("foo", 0, &.succ.pred).same?(map) # => true, no change
  #
  # map2 = Pf::Map[foo: 100, bar: 200]
  # map.merge(map2).same?(map)  # => true, no change
  # map2.merge(map).same?(map2) # => true, no change
  # ```
  #
  # If you want to enable `==` for our own object, you should include
  # `Pf::Eq`.
  #
  # ```
  # record Info, first_name : String, last_name : String
  #
  # people = Pf::Map
  #   .assoc(0, Info.new("John", "Doe"))
  #   .assoc(1, Info.new("Barbara", "Doe"))
  #
  # people.assoc(0, Info.new("John", "Doe")).same?(people) # => false
  #
  # struct Info
  #   include Pf::Eq
  # end
  #
  # people.assoc(0, Info.new("John", "Doe")).same?(people) # => true
  # ```
  #
  # Since `BidiMap` is backed by `Map`, the same applies to it. On the
  # other hand, elements of a `Set` are *keys* so they are always compared
  # using `==` eventually.
  struct Map(K, V)
    include Core
    include Enumerable({K, V})

    # Returns `true` if two mapping values *v1* and *v2* are equal, taking
    # `Pf::Eq` into account.
    def self.eqv?(v1 : V, v2 : V) : Bool forall V
      {% if V < ::Pf::Eq || V == ::Nil || V == ::Bool || V == ::Char || V == ::String || V == ::Symbol || V < ::Number::Primitive %}
        v1 == v2
      {% elsif V < ::Reference %}
        v1.same?(v2)
      {% else %}
        false
      {% end %}
    end

    private struct Entry(K, V)
      getter k : K
      getter v : V

      def initialize(@k : K, @v : V)
      end
    end

    private module Probes
      struct Fetch(K, V)
        include IProbeFetch(Entry(K, V))

        def initialize(@key : K)
        end

        def path : UInt64
          Core.hash64(@key)
        end

        def match?(stored : Entry(K, V)) : Bool
          @key == stored.k
        end
      end

      abstract struct Assoc(K, V)
        include IProbeAdd(Entry(K, V))

        def initialize(@key : K, @value : V)
        end

        def path : UInt64
          Core.hash64(@key)
        end

        def match?(stored : Entry(K, V)) : Bool
          @key == stored.k
        end

        def replace?(stored : Entry(K, V)) : Bool
          !Map.eqv?(@value, stored.v)
        end

        def value : Entry(K, V)
          Entry(K, V).new(@key, @value)
        end
      end

      struct AssocImm(K, V) < Assoc(K, V)
        def author : AuthorId
          AUTHOR_NONE
        end
      end

      struct AssocMut(K, V) < Assoc(K, V)
        getter author : AuthorId

        def initialize(key, value, @author)
          super(key, value)
        end
      end

      abstract struct Dissoc(K, V)
        include IProbeDelete(Entry(K, V))

        def initialize(@key : K)
        end

        def path : UInt64
          Core.hash64(@key)
        end

        def match?(stored : Entry(K, V)) : Bool
          @key == stored.k
        end
      end

      struct DissocImm(K, V) < Dissoc(K, V)
        def author : AuthorId
          AUTHOR_NONE
        end
      end

      struct DissocMut(K, V) < Dissoc(K, V)
        getter author : AuthorId

        def initialize(key, @author)
          super(key)
        end
      end
    end

    # Commits allow you to compose multiple edits into one, big edit of the map.
    # Thus you avoid creating many useless intermediate copies of the map.
    class Commit(K, V)
      @@id : Atomic(UInt64) = Atomic.new(AUTHOR_FIRST)

      # :nodoc:
      def self.genid
        @@id.add(1)
      end

      protected def initialize(@map : Map(K, V), @fiber : UInt64)
        @id = AuthorId.new(Commit.genid)
        @resolved = false
      end

      # Runs `Map#includes?` on the map built so far.
      def includes?(object) : Bool
        @map.includes?(object)
      end

      # Runs `Map#[]?` on the map built so far.
      def []?(key : K) : V?
        @map[key]?
      end

      # Runs `Map#[]` on the map built so far.
      def [](key : K) : V
        @map[key]
      end

      # Commits the association between *key* and *value* to the map.
      #
      # Raises `ResolvedError` if this commit is used outside of the transaction
      # (see `Map#transaction`) that produced it.
      #
      # Raises `ReadonlyError` if called by a fiber other than the fiber that
      # initiated the transaction.
      def assoc(key : K, value : V) : self
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == Core.fiber_id

        @map = @map.assoc!(key, value, @id)

        self
      end

      # Commits the removal of an association between *key* and *value* from
      # the map.
      #
      # Raises `ResolvedError` if this commit is used outside of the transaction
      # (see `Map#transaction`) that produced it.
      #
      # Raises `ReadonlyError` if called by a fiber other than the fiber that
      # initiated the transaction.
      def dissoc(key : K) : self
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == Core.fiber_id

        @map = @map.dissoc!(key, @id)

        self
      end

      # :nodoc:
      def resolve
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == Core.fiber_id

        @resolved = true
        @map
      end
    end

    # :nodoc:
    #
    # Kernel defines the basic ways of how `Map` can talk to `Node`.
    abstract struct Kernel(K, V)
      # Returns the amount of key-value pairs.
      abstract def size : Int32

      # Returns `true` if this and *other* kernels are the same (by reference,
      # if possible).
      abstract def same?(other : Kernel(K, V)) : Bool

      # Yields each key-value pair.
      abstract def each(& : {K, V} ->)

      # Returns the value associated with the given *key*.
      abstract def fetch?(key : K) : {V}?

      # Creates an association between *key* and *value*. Returns the modified
      # copy of this kernel.
      abstract def assoc(key : K, value : V) : Kernel(K, V)

      # Mutably creates an association between *key* and *value*. Returns the
      # modified copy of this kernel.
      abstract def assoc!(key : K, value : V, author : AuthorId) : Kernel(K, V)

      # Removes the association between *key* and some value, does nothing if
      # *key* does not exist. Returns the modified copy of this kernel.
      abstract def dissoc(key : K) : Kernel(K, V)

      # Mutably removes the association between *key* and some value, does nothing
      # if *key* does not exist. Returns the modified copy of this kernel.
      abstract def dissoc!(key : K, author : AuthorId) : Kernel(K, V)
    end

    # :nodoc:
    #
    # Optimized kernel implementation for an empty map.
    struct Kernel::Empty(K, V) < Kernel(K, V)
      def size : Int32
        0
      end

      def same?(other : Empty(K, V)) : Bool
        true
      end

      def same?(other) : Bool
        false
      end

      def each(& : {K, V} ->)
      end

      def fetch?(key : K) : {V}?
      end

      def assoc(key : K, value : V) : Kernel(K, V)
        One(K, V).new(key, value)
      end

      def assoc!(key : K, value : V, author : AuthorId) : Kernel(K, V)
        assoc(key, value)
      end

      def dissoc(key : K) : Kernel(K, V)
        self
      end

      def dissoc!(key : K, author : AuthorId) : Kernel(K, V)
        dissoc(key)
      end
    end

    # :nodoc:
    #
    # Optimized kernel implementation for a single-element map.
    struct Kernel::One(K, V) < Kernel(K, V)
      def initialize(@key : K, @value : V)
      end

      def size : Int32
        1
      end

      def same?(other : One(K, V)) : Bool
        {% begin %}
          {% if K < ::Reference %}
            p1 = @key.same?(other.@key)
          {% else %}
            p1 = @key == other.@key
          {% end %}

          {% if V < ::Reference %}
            p2 = @value.same?(other.@value)
          {% else %}
            p2 = @value == other.@value
          {% end %}

          p1 && p2
        {% end %}
      end

      def same?(other) : Bool
        false
      end

      def each(& : {K, V} ->)
        yield({@key, @value})
      end

      def fetch?(key : K) : {V}?
        key == @key ? {@value} : nil
      end

      def assoc(key : K, value : V) : Kernel(K, V)
        return One(K, V).new(key, value) if key == @key

        many = Many(K, V).new
        many.assoc(@key, @value).assoc(key, value)
      end

      def assoc!(key : K, value : V, author : AuthorId) : Kernel(K, V)
        assoc(key, value)
      end

      def dissoc(key : K) : Kernel(K, V)
        key == @key ? Empty(K, V).new : self
      end

      def dissoc!(key : K, author : AuthorId) : Kernel(K, V)
        dissoc(key)
      end
    end

    # :nodoc:
    #
    # Kernel implementation for a multi-element map.
    struct Kernel::Many(K, V) < Kernel(K, V)
      getter size : Int32

      def initialize(@node : Node(Entry(K, V)), @size : Int32)
      end

      def initialize
        initialize(node: Node(Entry(K, V)).new, size: 0)
      end

      def each(& : {K, V} ->)
        @node.each { |entry| yield({entry.k, entry.v}) }
      end

      def same?(other : Many(K, V)) : Bool
        @node.same?(other.@node)
      end

      def same?(other) : Bool
        false
      end

      def fetch?(key : K) : {V}?
        return unless entry_t = @node.fetch?(Probes::Fetch(K, V).new(key))

        entry, *_ = entry_t
        {entry.v}
      end

      def assoc(key : K, value : V) : Kernel(K, V)
        added, node = @node.add(Probes::AssocImm(K, V).new(key, value))
        Many(K, V).new(node, added ? @size + 1 : @size)
      end

      def assoc!(key : K, value : V, author : AuthorId) : Kernel(K, V)
        added, node = @node.add(Probes::AssocMut(K, V).new(key, value, author))
        Many(K, V).new(node, added ? @size + 1 : @size)
      end

      def dissoc(key : K) : Kernel(K, V)
        removed, node = @node.delete(Probes::DissocImm(K, V).new(key))
        Many(K, V).new(node, removed ? @size - 1 : @size)
      end

      def dissoc!(key : K, author : AuthorId) : Kernel(K, V)
        removed, node = @node.delete(Probes::DissocMut(K, V).new(key, author))
        Many(K, V).new(node, removed ? @size - 1 : @size)
      end
    end

    protected def initialize(@kernel : Kernel(K, V))
    end

    # Constructs an empty `Map`.
    def self.new : Map(K, V)
      new(Kernel::Empty(K, V).new)
    end

    # Constructs a `Map` from an *enumerable* of key-value pairs.
    def self.new(enumerable : Enumerable({K, V}))
      Map(K, V).new.concat(enumerable)
    end

    # A shorthand for `new.assoc`.
    def self.assoc(key : K, value : V) : Map(K, V)
      new(Kernel::One(K, V).new(key, value))
    end

    # :nodoc:
    def self.[]
      Map(K, V).new
    end

    # A shorthand syntax for creating a `Map` with string keys. The type
    # of the map's values is the union of the types of values in *entries*.
    #
    # ```
    # map = Pf::Map[name: "John Doe", age: 25]
    # map["name"] # => "John Doe"
    # map["age"]  # => 25
    #
    # typeof(map) # => Pf::Map(String, String | Int32)
    # ```
    def self.[](**entries)
      Map(String, typeof(Enumerable.element_type(entries.values))).transaction do |commit|
        entries.each { |k, v| commit.assoc(k.to_s, v) }
      end
    end

    # Shorthand for `new.transaction`.
    def self.transaction(& : Commit(K, V) ->) : Map(K, V)
      new.transaction { |commit| yield commit }
    end

    # Returns the number of associations in this map.
    def size : Int32
      @kernel.size
    end

    # Yields a `Commit` object which allows you to mutate a copy of `self`.
    #
    # - The commit object is marked as *resolved* after the block. You should not
    #   retain it. If you do, all operations on the object (including readonly ones)
    #   will raise `ResolvedError`.
    #
    # - If you pass the commit object to another fiber in the block, e.g. via
    #   a channel, and fiber yield immediately after that, the commit obviously
    #   would not be marked as *resolved* as the resolution code would not have
    #   been reached yet. However, if you then attempt to call mutation methods
    #   on the commit, another error, `ReadonlyError`, will be raised. *In other
    #   words, the yielded commit object is readonly for any other fiber except
    #   for the fiber that it was originally yielded to*.
    #
    # Returns `self` if the transaction did not *touch* the map. If the map was
    # changed but then the changes were reverted this method will return a new map.
    #
    # ```
    # map1 = Pf::Map(String, Int32).new
    # map2 = map1.transaction do |commit|
    #   commit.assoc("John Doe", 12)
    #   commit.assoc("Susan Doe", 34)
    #   commit.dissoc("John Doe")
    #   if "John Doe".in?(commit)
    #     commit.assoc("Mark Doe", 21)
    #   else
    #     commit.assoc("John Doe", 456)
    #     commit.assoc("Susan Doe", commit["Susan Doe"] + 1)
    #   end
    # end
    # map1 # => Pf::Map[]
    # map2 # => Pf::Map["John Doe" => 456, "Susan Doe" => 35]
    # ```
    def transaction(& : Commit(K, V) ->) : Map(K, V)
      commit = Commit.new(self, Core.fiber_id)
      yield commit
      commit.resolve
    end

    # Returns `true` if this map contains no mappings.
    def empty? : Bool
      size.zero?
    end

    # Yields each key-value pair to the block.
    def each(& : {K, V} ->) : Nil
      @kernel.each { |k, v| yield({k, v}) }
    end

    # Yields each key to the block.
    def each_key(& : K ->) : Nil
      each { |k, _| yield k }
    end

    # Yields each value to the block.
    def each_value(& : V ->) : Nil
      each { |_, v| yield v }
    end

    # Returns an array with all keys from this map. There is no
    # guaranteed order of keys.
    #
    # ```
    # map = Pf::Map[foo: 10, bar: 20]
    # map.keys # => ["foo", "bar"]
    # ```
    def keys : Array(K)
      keys = Array(K).new(size)
      each_key do |key|
        keys << key
      end
      keys
    end

    # Returns an array with all values from this map. There is no
    # guaranteed order of values.
    #
    # ```
    # map = Pf::Map[foo: 10, bar: 20]
    # map.values # => [10, 20]
    # ```
    def values : Array(V)
      values = Array(V).new(size)
      each_value do |key|
        values << key
      end
      values
    end

    # Returns the value associated with *key*, or `nil` if the value is absent.
    # The value is wrapped in a tuple to differentiate between `nil` as value
    # and `nil` as absence.
    #
    # ```
    # map = Pf::Map[name: "John Doe", job: nil]
    # map.fetch?("job")  # => {nil}
    # map.fetch?("name") # => {"John Doe"}
    # map.fetch?("age")  # => nil
    #
    # if name_t = map.fetch?("name")
    #   name, *_ = name_t
    #   name # => "John Doe"
    # end
    # ```
    def fetch?(key : K) : {V}?
      @kernel.fetch?(key)
    end

    # Returns the value mapped to *key*, or yields if *key* is absent.
    # This method mainly exists to circumvent nil as in value vs. nil
    # as in absence issue.
    def fetch(key : K, & : -> T) : V | T forall T
      return yield unless value_t = fetch?(key)

      value, *_ = value_t
      value
    end

    # Returns `true` if *key* is present in this map.
    #
    # ```
    # map = Pf::Map[foo: 100, bar: 200]
    # "foo".in?(map) # => true
    # "bar".in?(map) # => true
    # "baz".in?(map) # => false
    # ```
    def includes?(key : K) : Bool
      fetch(key) { return false }

      true
    end

    # :nodoc:
    def includes?(key) : Bool
      false
    end

    # Alias of `includes?`.
    def has_key?(key) : Bool
      includes?(key)
    end

    # Returns the value associated with *key*, or nil if *key* is absent.
    #
    # ```
    # map = Pf::Map[foo: 10, bar: 20]
    # map["foo"]? # => 10
    # map["bar"]? # => 20
    # map["baz"]? # => nil
    # ```
    def []?(key : K) : V?
      fetch(key) { return }
    end

    # Traverses nested maps/`Hash`es and returns the value, or `nil` if
    # the value is absent.
    #
    # ```
    # map = Pf::Map[foo: Pf::Map[bar: {100 => Pf::Map[baz: "Yay!"]}]]
    # map["foo", "bar", 100, "baz"]? # => "Yay!"
    # map["foo", "bar", 200]?        # => nil
    # ```
    def []?(key : K, *subkeys)
      dig?(key, *subkeys)
    end

    # :nodoc:
    def dig?(key : K, *subkeys)
      return unless value = self[key]?
      return unless value.responds_to?(:dig?)

      value.dig?(*subkeys)
    end

    # :nodoc:
    def dig?(key : K)
      self[key]?
    end

    # Returns the value associated with *key*. Raises `KeyError` if there is
    # no such value.
    #
    # ```
    # map = Pf::Map[foo: 10]
    # map["foo"] # => 10
    # map["bar"] # raises KeyError
    # ```
    def [](key : K) : V
      self[key]? || raise KeyError.new("Missing map key: #{key.inspect}")
    end

    # Traverses nested maps/`Hash`es and returns the value. Raises
    # `KeyError` if there is no value.
    #
    # ```
    # map = Pf::Map[foo: Pf::Map[bar: {100 => Pf::Map[baz: "Yay!"]}]]
    # map["foo", "bar", 100, "baz"] # => "Yay!"
    # map["foo", "bar", 200]        # raises KeyError
    # ```
    def [](key : K, *subkeys)
      dig(key, *subkeys)
    end

    # :nodoc:
    def dig(key : K, *subkeys)
      if (value = self[key]?) && value.responds_to?(:dig)
        return value.dig(*subkeys)
      end

      raise KeyError.new("Map value not diggable for key: #{key.inspect}")
    end

    # :nodoc:
    def dig(key : K)
      self[key]? || raise KeyError.new("Map value not diggable for key: #{key.inspect}")
    end

    # Returns a copy of `self` that contains the association between *key* and *value*.
    #
    # *Supports value equality.*
    #
    # ```
    # map = Pf::Map(String, Int32).new
    #
    # branch1 = map.assoc("foo", 100)
    # branch2 = map.assoc("foo", 200)
    #
    # map = map.assoc("bar", 300)
    #
    # map["foo"]? # => nil
    # map["bar"]? # => 300
    #
    # branch1["foo"]? # => 100
    # branch1["bar"]? # => nil
    #
    # branch2["foo"]? # => 200
    # branch2["bar"]? # => nil
    # ```
    def assoc(key : K, value : V) : Map(K, V)
      Map.new(@kernel.assoc(key, value))
    end

    protected def assoc!(key : K, value : V, author : AuthorId) : Map(K, V)
      Map.new(@kernel.assoc!(key, value, author))
    end

    # Returns an updated copy of `self`.
    #
    # - If there is no association for *key*, the copy contains an association
    #   between *key* and *default*.
    #
    # - If there is an association for *key*, its value is yielded to the block
    #   and the return value of the block is used as the next value of *key*.
    #
    # *Supports value equality.*
    #
    # ```
    # map = Pf::Map[foo: 100, bar: 200]
    # map.update("foo", 0, &.succ) # => Pf::Map{"foo" => 101, "bar" => 200}
    # map.update("baz", 0, &.succ) # => Pf::Map{"foo" => 100, "bar" => 200, "baz" => 0}
    # ```
    def update(key : K, default : V, & : V -> V)
      value = fetch(key) { return assoc(key, default) }
      assoc(key, yield value)
    end

    # Returns a copy of `self` that is guaranteed not to contain an association
    # with the given *key*.
    #
    # ```
    # map = Pf::Map[foo: 100, bar: 200]
    #
    # branch1 = map.dissoc("foo")
    # branch2 = map.dissoc("bar")
    #
    # map["foo"]? # => 100
    # map["bar"]? # => 200
    #
    # branch1["foo"]? # => nil
    # branch1["bar"]? # => 200
    #
    # branch2["foo"]? # => 100
    # branch2["bar"]? # => nil
    # ```
    def dissoc(key : K) : Map(K, V)
      Map(K, V).new(@kernel.dissoc(key))
    end

    protected def dissoc!(key : K, author : AuthorId) : Map(K, V)
      Map(K, V).new(@kernel.dissoc!(key, author))
    end

    # :nodoc:
    def merge(other : Map(K, V)) : Map(K, V)
      return other if empty?

      transaction do |commit|
        other.each { |k2, v2| commit.assoc(k2, v2) }
      end
    end

    # Returns a new map with associations from `self` and *other* combined.
    #
    # If some key is common both to `self` and *other*, *other*'s value
    # is preferred.
    #
    # Supports value equality if `K == K2` and `V == V2`.
    #
    # ```
    # a = Pf::Map[foo: 100, bar: 200]
    # b = Pf::Map[foo: "hello", baz: true, boo: 500]
    #
    # map = a.merge(b)
    # map # => Pf::Map{"foo" => "hello", "bar" => 200, "baz" => true, "boo" => 500}
    #
    # typeof(map) # => Pf::Map(String, String | Int32 | Bool)
    # ```
    def merge(other : Map(K2, V2)) : Map(K | K2, V | V2) forall K2, V2
      Map(K | K2, V | V2).transaction do |commit|
        self.each { |k, v1| commit.assoc(k.as(K | K2), v1.as(V | V2)) }
        other.each { |k, v2| commit.assoc(k.as(K | K2), v2.as(V | V2)) }
      end
    end

    # Returns a new map with assocations from `self` and *other* combined.
    #
    # If some key is common both to `self` and *other*, that key is
    # yielded to the block together with the two values. The return
    # value of the block is used as the final value.
    #
    # ```
    # a = Pf::Map[foo: 100, bar: 200, baz: 300]
    # b = Pf::Map[foo: 200, bar: 300.8, boo: 1000.5]
    #
    # map = a.merge(b) { |k, v1, v2| v1 + v2 }
    # map # => Pf::Map{"foo" => 300, "bar" => 500.8, "baz" => 300, "boo" => 1000.5}
    #
    # typeof(map) # => Pf::Map(String, Int32 | Float64)
    # ```
    def merge(other : Map(K2, V2), & : K, V, V2 -> V | V2) : Map(K | K2, V | V2) forall K2, V2
      Map(K | K2, V | V2).transaction do |commit|
        self.each { |k, v1| commit.assoc(k.as(K | K2), v1.as(V | V2)) }
        other.each do |k, v2|
          k = k.as(K | K2)
          if v1 = commit[k]?
            commit.assoc(k, (yield k.as(K), v1.as(V), v2.as(V2)).as(V | V2))
          else
            commit.assoc(k, v2.as(V | V2))
          end
        end
      end
    end

    # Returns a new map with associations from `self` and *other* combined, where
    # *other* is an enumerable of key-value pairs.
    #
    # *Supports value equality.*
    #
    # ```
    # map = Pf::Map[foo: 100, bar: 200, baz: 300]
    # map.concat([{"x", 123}, {"y", 456}]) # => Pf::Map[foo: 100, bar: 200, baz: 300, x: 123, y: 456]
    # ```
    def concat(other : Enumerable({K, V})) : Map(K, V)
      transaction do |commit|
        other.each { |k2, v2| commit.assoc(k2, v2) }
      end
    end

    # Returns a copy of `self` which includes only associations for which
    # the block is *truthy*.
    #
    # *Supports value equality.*
    #
    # ```
    # map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
    # map.select { |_, v| v.even? } # => Pf::Map{"foo" => 2, "baz" => 4}
    # ```
    def select(& : {K, V} -> Bool) : Map(K, V)
      transaction do |commit|
        each { |k, v| commit.dissoc(k) unless yield({k, v}) }
      end
    end

    # Returns a new map which includes only associations with the given *keys*.
    #
    # ```
    # map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
    # map.select({"foo", "boo"}) # => Pf::Map{"foo" => 2, "boo" => 5}
    # map.select("foo", "boo")   # => Pf::Map{"foo" => 2, "boo" => 5}
    # ```
    def select(keys : Enumerable)
      Map(K, V).transaction do |commit|
        keys.each do |key|
          next unless value = self[key]?
          commit.assoc(key, value)
        end
      end
    end

    # :ditto:
    def select(*keys)
      self.select(keys)
    end

    # Returns a copy of `self` which includes only associations for which
    # the block is *falsey*.
    #
    # *Supports value equality.*
    #
    # ```
    # map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
    # map.reject { |_, v| v.even? } # => Pf::Map{"bar" => 3, "boo" => 5}
    # ```
    def reject(& : {K, V} -> Bool) : Map(K, V)
      self.select { |k, v| !yield({k, v}) }
    end

    # Returns a new map which is guaranteed not to include the given *keys*.
    #
    # ```
    # map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
    # map.reject({"foo", "boo"}) # => Pf::Map{"bar" => 3, "baz" => 4}
    # map.reject("foo", "boo")   # => Pf::Map{"bar" => 3, "baz" => 4}
    # ```
    def reject(keys : Enumerable)
      transaction do |commit|
        keys.each { |key| commit.dissoc(key) }
      end
    end

    # :ditto:
    def reject(*keys)
      self.reject(keys)
    end

    # Returns a copy of `self` without `nil` values.
    #
    # ```
    # map = Pf::Map[foo: nil, bar: 123]
    # map.compact # => Pf::Map{"bar" => 123}
    #
    # typeof(map)         # => Pf::Map(String, Int32?)
    # typeof(map.compact) # => Pf::Map(String, Int32)
    # ```
    def compact
      Map(K, typeof(Enumerable.element_type(self)[1].not_nil!)).transaction do |commit|
        each do |key, value|
          next unless value
          commit.assoc(key, value)
        end
      end
    end

    # Same as `map`, but returns `Map` instead of an array.
    #
    # If the block returns more than one value for the same key, the last
    # yielded value is preferred.
    #
    # Supports value equality if `K == K2` and `V == V2`.
    #
    # ```
    # map = Pf::Map[foo: "John Doe", bar: "Samantha Doe"]
    # map.fmap { |k, v| {k.upcase, v.upcase} } # => Pf::Map{"FOO" => "JOHN DOE", "BAR" => "SAMANTHA DOE"}
    # ```
    def fmap(& : {K, V} -> {K2, V2}) : Map(K2, V2) forall K2, V2
      {% if K == K2 && V == V2 %}
        same = true
        map = Map(K, V).transaction do |commit|
          each do |key, value|
            newkey, newvalue = yield({key, value})
            commit.assoc(newkey, newvalue)
            next unless same
            unless oldvalue_t = fetch?(newkey)
              same = false
              next
            end
            oldvalue, *_ = oldvalue_t
            same = Map.eqv?(oldvalue, newvalue)
          end
        end
        same ? self : map
      {% else %}
        to_pf_map { |k, v| yield({k, v}) }
      {% end %}
    end

    # Transforms keys: same as `fmap`, but only yields keys from this map.
    #
    # Supports value equality if `K == K2`.
    #
    # ```
    # map = Pf::Map[foo: "John Doe", bar: "Samantha Doe"]
    # map.map_key(&.upcase) # => Pf::Map{"FOO" => "John Doe", "BAR" => "Samantha Doe"}
    # ```
    def map_key(& : K -> K2) : Map(K2, V) forall K2
      fmap { |k, v| {(yield k), v} }
    end

    # Transforms values: same as `fmap`, but only yields values from
    # this map.
    #
    # Supports value equality if `V == V2`.
    #
    # ```
    # map = Pf::Map[foo: "John Doe", bar: "Samantha Doe"]
    # map.map_value(&.upcase) # => Pf::Map{"foo" => "JOHN DOE", "bar" => "SAMANTHA DOE"}
    # ```
    def map_value(& : V -> V2) : Map(K, V2) forall V2
      fmap { |k, v| {k, (yield v)} }
    end

    # Returns `true` if `self` and *other* refer to the same map in memory.
    #
    # Due to the way `Map` is implemented, this method can be used as
    # a cheap way to detect changes.
    #
    # ```
    # map1 = Pf::Map[foo: 123, bar: 456]
    # map2 = map1.assoc("foo", 123)
    # map1.same?(map2) # => true
    # ```
    def same?(other : Map(K, V)) : Bool
      @kernel.same?(other.@kernel)
    end

    # :nodoc:
    def same?(other) : Bool
      false
    end

    # Returns a new `Map` whose values are deeply cloned versions of
    # those from `self`. That is, returns a deep copy of `self`.
    #
    # Keys are not cloned (if you need to clone keys then the last thing
    # to help you is a persistent immutable map!).
    #
    # ```
    # map = Pf::Map[foo: [1, 2, 3], bar: [4, 5, 6]]
    # map2 = map.clone
    #
    # map["foo"][0] = 100
    #
    # map  # => Pf::Map{"foo" => [100, 2, 3], "bar" => [4, 5, 6]}
    # map2 # => Pf::Map{"foo" => [1, 2, 3], "bar" => [4, 5, 6]}
    # ```
    def clone : Map(K, V)
      {% if V == ::Nil || V == ::Bool || V == ::Char || V == ::String || V == ::Symbol || V < ::Number::Primitive %}
        return self
      {% end %}

      # It sounds like a dangerous thing to say but I guess exec_recursive_clone
      # isn't needed here, it's the responsibility of the value (and we never
      # actually clone Nodes anyway?)
      Map(K, V).transaction do |commit|
        each { |k, v| commit.assoc(k.clone, v.clone) }
      end
    end

    # Compares `self` with *other*. Returns `true` if all associations are
    # the same (values are compared using `==`).
    def ==(other : Map) : Bool
      return true if same?(other)
      return false unless size == other.size

      each do |k, v1|
        v2 = other.fetch(k) { return false }
        return false unless v1 == v2
      end

      true
    end

    # See `Object#hash(hasher)`
    def hash(hasher)
      # Same as in `Hash#hash`

      result = hasher.result

      copy = hasher
      copy = self.class.hash(copy)
      result &+= copy.result

      each do |k, v|
        copy = hasher
        copy = k.hash(copy)
        copy = v.hash(copy)
        result &+= copy.result
      end

      result.hash(hasher)
    end

    def inspect(io)
      to_s(io)
    end

    def to_s(io)
      io << "Pf::Map{"
      join(io, ", ") do |(k, v)|
        k.inspect(io)
        io << " => "
        v.inspect(io)
      end
      io << "}"
    end

    def pretty_print(pp) : Nil
      pp.list("Pf::Map{", self, "}") do |k, v|
        pp.group do
          k.pretty_print(pp)
          pp.text " =>"
          pp.nest do
            pp.breakable
            v.pretty_print(pp)
          end
        end
      end
    end
  end
end

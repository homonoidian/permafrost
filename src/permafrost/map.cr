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

    # Returns if two mapping values *v1* and *v2* are equal taking `Pf::Eq`
    # into account.
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

        def match?(stored) : Bool
          stored.is_a?(Entry) && @key == stored.k
        end

        def replace?(stored) : Bool
          !(stored.is_a?(Entry) && Map.eqv?(@value, stored.v))
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

    class Commit(K, V)
      @@id : Atomic(UInt64) = Atomic.new(AUTHOR_FIRST)

      def self.genid
        @@id.add(1)
      end

      protected def initialize(@map : Map(K, V), @fiber : UInt64)
        @id = AuthorId.new(Commit.genid)
        @resolved = false
      end

      delegate :[]?, to: @map

      def assoc(key : K, value : V)
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == fiber_id

        @map = @map.assoc!(key, value, @id)

        self
      end

      def dissoc(key : K)
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == fiber_id

        @map = @map.dissoc!(key, @id)

        self
      end

      def resolve
        raise ResolvedError.new if @resolved
        raise ReadonlyError.new unless @fiber == fiber_id

        @resolved = true
        @map
      end
    end

    # Returns the number of mappings in this map.
    getter size : Int32

    protected def initialize(@node : Node(Entry(K, V)), @size = 0)
    end

    # Returns a new empty `Map`.
    def self.new : Map(K, V)
      new(Node(Entry(K, V)).new)
    end

    # Returns a map with mappings from an *enumerable* of key-value pairs.
    def self.new(enumerable : Enumerable({K, V}))
      Map(K, V).new.merge(enumerable)
    end

    # A shorthand for `new.assoc`.
    def self.assoc(key : K, value : V) : Map(K, V)
      Map(K, V).new.assoc(key, value)
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

    # Yields a `Commit` object which allows you to mutate a copy of `self`.
    #
    # - The commit object is marked as *resolved* after the block. You should not
    #   retain it. If you do, all operations on the object (including readonly ones)
    #   will raise `ResolvedError`.
    # - If you pass the commit object to another fiber in the block, e.g. via
    #   a channel, and fiber yield immediately after that, the commit obviously
    #   would not be marked as *resolved* as the resolution code would not have
    #   been reached yet. However, if you then attempt to call mutation methods
    #   on the commit, another error, `ReadonlyError`, will be raised. *In other
    #   words, the yielded commit object is readonly in any other fiber except
    #   for the fiber that it was originally yielded to*.
    def transaction(& : Commit(K, V) ->) : Map(K, V)
      commit = Commit.new(self, fiber_id)
      yield commit
      commit.resolve
    end

    # Returns `true` if this map contains no mappings.
    def empty? : Bool
      size.zero?
    end

    # Yields each key-value pair to the block.
    def each(& : {K, V} ->) : Nil
      @node.each { |entry| yield({entry.k, entry.v}) }
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

    def fetch?(key : K) : {V}?
      return unless entry_t = @node.fetch?(Probes::Fetch(K, V).new(key))

      entry, *_ = entry_t
      {entry.v}
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

    # Returns the value mapped to *key*, or nil if *key* is absent.
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

    # Returns the value mapped to *key*. Raises `KeyError` if there is
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

    # Returns a copy of `self` that contains the mapping of *key* to *value*.
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
      added, node = @node.add(Probes::AssocImm(K, V).new(key, value))
      Map.new(node, added ? @size + 1 : @size)
    end

    protected def assoc!(key : K, value : V, author : AuthorId) : Map(K, V)
      added, node = @node.add(Probes::AssocMut(K, V).new(key, value, author))
      Map.new(node, added ? @size + 1 : @size)
    end

    # Returns an updated copy of `self`.
    #
    # - If there is no mapping for *key*, the copy contains a mapping of
    # *key* to *default*.
    #
    # - If there is a mapping for *key*, its value is yielded to the block
    # and the return value of the block is used as the next value of *key*.
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

    # Returns a copy of `self` that is guaranteed not to contain a mapping
    # for *key*.
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
      removed, node = @node.delete(Probes::DissocImm(K, V).new(key))
      Map.new(node, removed ? @size - 1 : @size)
    end

    protected def dissoc!(key : K, author : AuthorId) : Map(K, V)
      removed, node = @node.delete(Probes::DissocMut(K, V).new(key, author))
      Map.new(node, removed ? @size - 1 : @size)
    end

    # :nodoc:
    def merge(other : Map(K, V)) : Map(K, V)
      return other if empty?

      transaction do |commit|
        other.each { |k2, v2| commit.assoc(k2, v2) }
      end
    end

    # Returns a new map with mappings from `self` and *other* combined.
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

    # Returns a new map with mappings from `self` and *other* combined.
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

    def merge(other : Enumerable({K, V})) : Map(K, V)
      transaction do |commit|
        other.each { |k2, v2| commit.assoc(k2, v2) }
      end
    end

    # Returns a copy of `self` which includes only mappings for which
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

    # Returns a new map which includes only mappings with the given *keys*.
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

    # Returns a copy of `self` which includes only mappings for which
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

    # :nodoc:
    delegate :object_id, to: @node

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
      object_id == other.object_id
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
      reduce(Map(K, V).new) { |map, (k, v)| map.assoc(k.clone, v.clone) }
    end

    # Compares `self` with *other*. Returns `true` if all mappings are
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

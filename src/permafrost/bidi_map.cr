module Pf
  # A thread-safe, persistent, unordered bidirectional map.
  #
  # See also: `Map`.
  struct BidiMap(K, V)
    include Enumerable({K, V})

    protected def initialize(@valueof : Pf::Map(K, V), @keyof : Pf::Map(V, K))
    end

    # Returns a new empty `BidiMap`.
    #
    # ```
    # bidi = Pf::BidiMap(String, Int32).new
    # bidi.empty? # => true
    # ```
    def self.new : BidiMap(K, V)
      new(valueof: Pf::Map(K, V).new, keyof: Pf::Map(V, K).new)
    end

    # Returns a map with mappings from an *enumerable* of key-value pairs.
    def self.new(enumerable : Enumerable({K, V})) : BidiMap(K, V)
      enumerable.reduce(BidiMap(K, V).new) { |bidi, (k, v)| bidi.assoc(k, v) }
    end

    # A shorthand for `new.assoc`.
    def self.assoc(key : K, value : V) : BidiMap(K, V)
      BidiMap(K, V).new.assoc(key, value)
    end

    # Returns `true` if this map contains no mappings.
    def empty? : Bool
      @valueof.empty?
    end

    # Returns the number of mappings.
    def size : Int32
      @valueof.size
    end

    # Yields each key-value pair to the block.
    def each(& : {K, V} ->) : Nil
      @valueof.each { |k, v| yield({k, v}) }
    end

    # Returns the key mapped to the given *value*, or nil if there is
    # no such key.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.key_for?(100) # => :foo
    # bidi.key_for?(200) # => :bar
    # bidi.key_for?(300) # => nil
    # ```
    def key_for?(value : V) : K?
      @keyof[value]?
    end

    # Returns the key mapped to the given *value*. If there is no such
    # key raises `KeyError`.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.key_for(100) # => :foo
    # bidi.key_for(200) # => :bar
    # bidi.key_for(300) # raises KeyError
    # ```
    def key_for(value : V) : K?
      key_for?(value) || raise KeyError.new("Missing bidirectional map key for value: #{value}")
    end

    # Returns the value mapped to the given *key*, or nil if there is
    # no such value.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.value_for?(:foo) # => 100
    # bidi.value_for?(:bar) # => 200
    # bidi.value_for?(:baz) # => nil
    # ```
    def value_for?(key : K) : V?
      @valueof[key]?
    end

    # Returns the value mapped to the given *key*. If there is no such
    # value raises `KeyError`.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.value_for(:foo) # => 100
    # bidi.value_for(:bar) # => 200
    # bidi.value_for(:baz) # raises KeyError
    # ```
    def value_for(key : K) : V?
      value_for?(key) || raise KeyError.new("Missing bidirectional map value for key: #{key.inspect}")
    end

    # Returns `true` if this map contains a mapping with the given *value*.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.has_key_for?(100) # => true
    # bidi.has_key_for?(200) # => true
    # bidi.has_key_for?(300) # => false
    # ```
    def has_key_for?(value) : Bool
      @keyof.includes?(value)
    end

    # Returns `true` if this map contains a mapping with the given *key*.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.has_value_for?(:foo) # => true
    # bidi.has_value_for?(:bar) # => true
    # bidi.has_value_for?(:baz) # => false
    # ```
    def has_value_for?(key) : Bool
      @valueof.includes?(key)
    end

    # Returns a copy of `self` that contains the mapping of *key* to
    # *value*. and of *value* to *key*.
    #
    # *Supports value equality*.
    #
    # ```
    # bidi = Pf::BidiMap(String, Int32).new
    # bidi.assoc("hello", 100) # => Pf::BidiMap{"hello" <=> 100}
    # ```
    def assoc(key : K, value : V) : BidiMap(K, V)
      if v = value_for?(key)
        return self if Map.eqv?(v, value)
        keyof = @keyof.dissoc(v)
      else
        keyof = @keyof
      end

      valueof = (k = key_for?(value)) ? @valueof.dissoc(k) : @valueof

      BidiMap.new(valueof.assoc(key, value), keyof.assoc(value, key))
    end

    # Returns a copy of `self` which is guaranteed not to have a mapping
    # with the given *key*.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.dissoc_by_key(:foo) # => Pf::BidiMap{:bar <=> 200}
    # ```
    def dissoc_by_key(key : K) : BidiMap(K, V)
      return self unless value = value_for?(key)

      BidiMap.new(@valueof.dissoc(key), @keyof.dissoc(value))
    end

    # Returns a copy of `self` which is guaranteed not to have a mapping
    # with the given *value*.
    #
    # ```
    # bidi = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi.dissoc_by_value(200) # => Pf::BidiMap{:foo <=> 100}
    # ```
    def dissoc_by_value(value : V) : BidiMap(K, V)
      return self unless key = key_for?(value)

      BidiMap.new(@valueof.dissoc(key), @keyof.dissoc(value))
    end

    # Returns `true` if `self` and *other* refer to the same map in memory.
    #
    # Due to the way `BidiMap` is implemented, this method can be used
    # as a cheap way to detect changes.
    #
    # ```
    # bidi1 = Pf::BidiMap.assoc(:foo, 100).assoc(:bar, 200)
    # bidi2 = bidi1.assoc(:foo, 100)
    # bidi1.same?(bidi2) # => true
    # ```
    def same?(other : BidiMap(K, V)) : Bool
      @valueof.same?(other.@valueof) && @keyof.same?(other.@keyof)
    end

    # :nodoc:
    def same?(other) : Bool
      false
    end

    # Returns `true` if the bidirectional maps are equal.
    def_equals @valueof, @keyof

    # See `Object#hash(hasher)`.
    def hash(hasher)
      result = hasher.result

      copy = hasher
      copy = self.class.hash(copy)
      result &+= copy.result

      copy = hasher
      copy = @valueof.hash(copy)
      result &+= copy.result

      copy = hasher
      copy = @keyof.hash(copy)
      result &+= copy.result

      result.hash(hasher)
    end

    def inspect(io)
      to_s(io)
    end

    def to_s(io)
      io << "Pf::BidiMap{"
      join(io, ", ") do |(k, v)|
        k.inspect(io)
        io << " <=> "
        v.inspect(io)
      end
      io << "}"
    end

    def pretty_print(pp) : Nil
      pp.list("Pf::BidiMap{", self, "}") do |k, v|
        pp.group do
          k.pretty_print(pp)
          pp.text " <=>"
          pp.nest do
            pp.breakable
            v.pretty_print(pp)
          end
        end
      end
    end
  end
end

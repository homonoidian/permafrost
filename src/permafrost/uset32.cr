# A thread-safe, persistent set of 32-bit unsigned integers.
#
# TODO: with this architecture, it is possible to union very large consecutive
# integer spans really quickly by setting presence = UInt[16/32]::MAX and setting
# fully covered bitmaps to UInt64::MAX. Bitmaps on the edges are union'd the way
# we do it right now. This would probably require introducing a third option for
# op rhs: right now we have Trie and TrieP (trie path), and to implement this we'd
# need to have TrieSpan as well.
#
# ## How it works?
#
# The most important takeaway is that with USet32, *integer magnitude directly
# affects performance*.
#
# See the diagram below.
#
# ```text
#                 (0-31)             (0-15)           (0-15)
# LSB          bitmap index         n0 index         n2 index       MSB
#                ─────────           ───────         ───────
#    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#    ───────────           ─────────         ───────         ───────
#     bit index           chunk index        n1 index        n3 index
#       (0-63)              (0-31)            (0-15)          (0-15)
#
#
#
#
#     ┌─────┐                        ▲
#     │N3   │                        │
#     └──┬──┘                        │
#        │  16-way branch            │
#        ▼                           │
#     ┌─────┐                        │
#     │N2   │                        │
#     └──┬──┘                        │
#        │  16-way branch            │
#        ▼                           │
#     ┌─────┐                        │
#     │N1   │                        │
#     └──┬──┘                        │
#        │  16-way branch            │
#        ▼                           │
#     ┌─────┐                        │
#     │N0   │                        │
#     └──┬──┘                        │
#        │  16-way branch            │  instantiated on-demand
#        ▼                           │  as the numbers grow
#   ┌─────────┐                      │
#   │wide node│                      │
#   └────┬────┘                      │
#        │  32-way branch            │
#        ▼                           │
#   ┌─────────┐                      │
#   │  chunk  │                      │
#   └────┬────┘                      │
#        │  32-way branch            │
#        ▼                           │
#   ┌───────────────────────────┐    │
#   │ bitmap                    │    │
#   │                           │    │
#   │ 0 0 0 0 0 0 0 ... 0 0 0 0 │    │
#   │ ───────────────────────── │    │
#   │          64 bits          │    │
#   └───────────────────────────┘    │
# ```
#
# USet32 effectively "reifies" the number tree (each number is a path through
# that tree), providing an indexing data structure on top of the u32 number line.
#
# Note how this implementation penalizes large numbers or sets containing large
# numbers (numbers far away from origin).
#
# Bitmaps are very cheap, so if your numbers are frequently in the 0-63 range, you're
# well set. The larger your number, the more allocation overhead you will have and
# the "taller" the tree will grow.
#
# Everything from *chunk* upwards adds an allocation / a pointer dereference. On
# one hand, that's nice because you will copy less and share more. On the other hand,
# modern CPUs penalize pointer chasing so you're going to suffer: dozens of nanoseconds
# up to 100ns for an insertion is not unheard of.
#
# We will probably provide support for USet64-256 in the future, because as you can see,
# this construction scales rather trivially; and USet256 especially would be useful for
# storing hashes such as SHA256 and BLAKE3. In that case, easing indirection and control
# overhead would become a high-priority goal.
#
# ## Performance
#
# Let's add all i32s. We can't add all u32s because BitArray crashes on that. We don't
# want to crash our only competitor in Crystal-land.
#
# ```
# require "benchmark"
# require "bit_array"
#
# Benchmark.ips do |x|
#   x.report("uset32") do
#     _ = Pf::USet32.transaction do |set|
#       (0..Int32::MAX).each do |n|
#         set << n.to_u32
#       end
#     end
#   end
#
#   x.report("bit array") do
#     bits = BitArray.new(Int32::MAX)
#     (0..Int32::MAX).each do |n|
#       bits.unsafe_put(n, true)
#     end
#   end
# end
# ```
#
# This reports the following on my machine (Ryzen 3 2200G):
#
# ```text
#    uset32   9.28m (107.77s ) (± 0.00%)  4.79GB/op  46.95× slower
# bit array 435.66m (  2.30s ) (± 1.14%)   256MB/op        fastest
# ```
#
# Horrendous, isn't it? Except remember that bit array allocates all the memory upfront,
# and does a neat sequ pass where it doesn't follow even a single pointer. Paradise for
# a modern CPU!
#
# Now, USet32 is a dynamic, immutable set that is explicitly designed in such a way that
# large numbers are penalized (versus, say, Roaring bitmaps, where magnitude does not
# matter and instead small *bitmaps* are penalized). USet32 lets you work with small
# numbers practically for free.
#
# If you have a different origin far from zero in your domain, you can normalize the numbers
# before inserting them into `USet32`. To support negative numbers, create two sets: one for
# negative numbers and another for positive ones. This is also the way to store `Int32`s efficiently,
# since their raw binary representation is *very* far from zero if cast to `UInt32`.
#
# USet32 is particularly well-suited for recording small, sequential ids, with an occasional
# immutable add or set operation. USet32 is suited for situations where you have thousands
# of small immutable sets, especially when they have a common ancestor.
#
# In fact, USet32 works beautifully well for set operations, since, point A, it's a trie,
# and point B, we have bitmaps at the leaves. This is almost perfect for any kind of set
# operation, be it union, intersection, difference, etc.
struct Pf::USet32
  include Enumerable(UInt32)

  private alias USet = Kit::USet

  # :nodoc:
  alias Kernel = Empty | Nonempty

  # :nodoc:
  record Empty

  # :nodoc:
  alias Nonempty = USet::Trie

  # :nodoc:
  def initialize(@kernel : Kernel)
  end

  def self.additive_identity : self
    new
  end

  # Constructs an empty set.
  def self.new : USet32
    new(Empty.new)
  end

  # Construct a set from the given enumerable *ee*.
  def self.new(ee : Enumerable(UInt32)) : USet32
    transaction do |set|
      ee.each { |value| set << value }
    end
  end

  # Exposes mutable versions of `USet32` methods to let you construct your
  # sets quickly.
  struct Commit
    # :nodoc:
    def initialize(@ptr : Kernel*)
    end

    # Runs `USet32#includes?` on the set built so far.
    def includes?(value : UInt32) : Bool
      peek.includes?(value)
    end

    # Runs `USet32#rank` on the set built so far.
    def rank(value : UInt32) : UInt32
      peek.rank(value)
    end

    # Adds *value* to this set.
    def <<(value : UInt32) : self
      case k = @ptr.value
      in Empty    then @ptr.value = USet.trie(USet.path(value))
      in Nonempty then @ptr.value = USet.union!(k, USet.path(value))
      end

      self
    end

    private def peek : USet32
      USet32.new(@ptr.value)
    end

    def pretty_print(pp)
      pp.list("USet32::Commit[", peek, "]")
    end

    def inspect(io)
      io << "USet32::Commit["
      peek.join(io, ", ") { |el| el.inspect(io) }
      io << "]"
    end

    def to_s(io)
      inspect(io)
    end
  end

  # Lets you build a possibly large set using `Commit`, which offers mutable versions
  # of methods from `USet32`.
  #
  # WARNING: The yielded `Commit` must, under no circumstances, outlive the block or
  # escape it otherwise, through retained closures, instance variables, etc. It uses
  # pointers into stack-allocated memory, so using it after the block returns
  # will lead to UB.
  #
  # ```
  # set = Pf::USet32.transaction do |commit|
  #   commit << 1
  #   commit << 2
  #   if commit.includes?(2)
  #     commit << 3
  #   end
  # end
  #
  # set # Pf::USet32[1, 2, 3]
  # ```
  def self.transaction(& : Commit ->) : USet32
    instance = uninitialized Kernel[1]
    instance[0] = Empty.new

    yield Commit.new(instance.to_unsafe)

    new(instance[0])
  end

  # Constructs a set with the given *values*.
  def self.[](*values : UInt32) : USet32
    transaction do |commit|
      values.each do |value|
        commit << value
      end
    end
  end

  # Constructs an empty set.
  def self.[] : USet32
    new
  end

  # Returns `true` if this set contains *value*. Returns `false` otherwise.
  #
  # ```
  # set = Pf::USet32[1, 2, 3]
  # set.includes?(2)   # => true
  # set.includes?(100) # => false
  # ```
  def includes?(value) : Bool
    case k = @kernel
    in Empty    then false
    in Nonempty then USet.includes?(k, value)
    end
  end

  # Returns the number of integers in this set (as an `Int32`).
  #
  # ```
  # set = Pf::USet32[1, 2, 3]
  # set.size # => 3
  # ```
  def size : Int32
    usize.to_i
  end

  # Returns the number of integers in this set (as a `UInt32`).
  def usize : UInt32
    case k = @kernel
    in Empty    then 0u32
    in Nonempty then USet.cardinality(k)
    end
  end

  # Returns the minimum excluded value (mex) of this set.
  #
  # ```
  # Pf::USet32[0, 1, 2, 3].mex # => 4
  # Pf::USet32[1, 2, 3].mex    # => 0
  # Pf::USet32[0, 1, 3].mex    # => 2
  # ```
  def mex : UInt32
    case k = @kernel
    in Empty then 0u32
    in Nonempty
      mex, _ = USet.mex(k)
      mex
    end
  end

  # Returns the number of integers less than *value* in this set. Works
  # even if *value* is absent.
  #
  # ```
  # Pf::USet32[1, 2, 3, 100].rank(1)    # => 0
  # Pf::USet32[1, 2, 3, 100].rank(2)    # => 1
  # Pf::USet32[1, 2, 3, 100].rank(3)    # => 2
  # Pf::USet32[1, 2, 3, 100].rank(90)   # => 3
  # Pf::USet32[1, 2, 3, 100].rank(100)  # => 3
  # Pf::USet32[1, 2, 3, 100].rank(1234) # => 4
  # ```
  #
  # As a side effect, you can use this method for sorting (similar to bisection
  # in spirit).
  #
  # ```
  # people = [
  #   {"Alice", 32},
  #   {"Bob", 45},
  #   {"Charlie", 28},
  #   {"Diana", 36},
  #   {"Eve", 29},
  # ]
  #
  # sorted = [] of {String, Int32}
  #
  # Pf::USet32.transaction do |uset|
  #   people.each do |name, age|
  #     sorted.insert(uset.rank(age.to_u32), {name, age})
  #     uset << age.to_u32
  #   end
  # end
  #
  # pp sorted # => [{"Charlie", 28}, {"Eve", 29}, {"Alice", 32}, {"Diana", 36}, {"Bob", 45}]
  # ```
  def rank(value : UInt32) : UInt32
    case k = @kernel
    in Empty    then 0u32
    in Nonempty then USet.rank(k, value)
    end
  end

  # Returns `true` if all integers in this set are contained on *other*. Returns
  # `false` otherwise.
  #
  # ```
  # xs = Pf::USet32[1, 2, 3]
  # ys = Pf::USet32[1, 2, 3, 4, 5, 6]
  #
  # xs.subset_of?(ys) # => true
  # ys.subset_of?(xs) # => false
  # ```
  def subset_of?(other : USet32) : Bool
    return false unless size <= other.size

    sm, lg = @kernel, other.@kernel

    case {sm, lg}
    in {Empty, Empty}, {Empty, Nonempty}
      # An empty set is a subset of itself and of any set.
      true
    in {Nonempty, Empty}
      false
    in {Nonempty, Nonempty}
      USet.subset?(lg, sm)
    end
  end

  # Returns `true` if all integers in this set are contained in *other*, and
  # *other* is larger than this set. Returns `false` otherwise.
  #
  # ```
  # xs = Pf::USet32[1, 2, 3]
  # ys = Pf::USet32[1, 2, 3, 4, 5, 6]
  #
  # xs.proper_subset_of?(ys) # => true
  #
  # ys.subset_of?(ys)        # => true
  # ys.proper_subset_of?(ys) # => false
  # ```
  def proper_subset_of?(other : USet32) : Bool
    return false unless size < other.size

    subset_of?(other)
  end

  # Returns `true` if this set contains all integers from *other*. Returns
  # `false` otherwise.
  #
  # ```
  # xs = Pf::USet32[1, 2, 3]
  # ys = Pf::USet32[1, 2, 3, 4, 5, 6]
  #
  # xs.superset_of?(ys) # => false
  # ys.superset_of?(xs) # => true
  # ```
  def superset_of?(other : USet32) : Bool
    other.subset_of?(self)
  end

  # Returns `true` if this set contains all integers from *other*, and *other*
  # is smaller than this set. Returns `false` otherwise.
  #
  # ```
  # xs = Pf::USet32[1, 2, 3]
  # ys = Pf::USet32[1, 2, 3, 4, 5, 6]
  #
  # ys.proper_superset_of?(xs) # => true
  #
  # ys.superset_of?(ys)        # => true
  # ys.proper_superset_of?(ys) # => false
  # ```
  def proper_superset_of?(other : USet32) : Bool
    other.proper_subset_of?(self)
  end

  # Returns `true` if this set has common integers with *other*. Returns
  # `false` otherwise.
  #
  # ```
  # xs = Pf::USet32[1, 2, 3]
  # ys = Pf::USet32[4, 5, 6]
  # zs = Pf::USet32[3, 5, 6]
  #
  # xs.intersects?(ys) # => false, nothing in common
  # xs.intersects?(zs) # => true, they both have `3`
  # ```
  def intersects?(other : USet32) : Bool
    k0, k1 = @kernel, other.@kernel

    case {k0, k1}
    in {Empty, _}, {Nonempty, Empty}
      false
    in {Nonempty, Nonempty}
      USet.intersects?(k0, k1)
    end
  end

  # Yields integers stored in this set.
  def each(& : UInt32 ->) : Nil
    case k = @kernel
    in Empty
    in Nonempty
      USet.each(0u32, k) { |value| yield value }
    end
  end

  # Returns a copy of this set with *value* present.
  #
  # ```
  # set = Pf::USet32[1, 2, 3]
  #
  # set.add(4) # => Pf::USet32[1, 2, 3, 4]
  # set        # => Pf::USet32[1, 2, 3]
  # ```
  def add(value : UInt32) : USet32
    case k = @kernel
    in Empty    then USet32.new(USet.trie(USet.path(value)))
    in Nonempty then USet32.new(USet.union(k, USet.path(value)))
    end
  end

  # Returns a copy of this set with *value* present, followed by a boolean
  # indicating whether *value* was added during the call.
  #
  # ```
  # set = Pf::USet32[1, 2, 3]
  #
  # set.add?(4) # => {Pf::USet32[1, 2, 3, 4], true}
  # set.add?(1) # => {Pf::USet32[1, 2, 3], false}
  #
  # set # => Pf::USet32[1, 2, 3]
  # ```
  def add?(value : UInt32) : {USet32, Bool}
    case k = @kernel
    in Empty
      {USet32.new(USet.trie(USet.path(value))), true}
    in Nonempty
      k1 = USet.union(k, USet.path(value))
      if k == k1 # Bitmap or pointer equality
        return self, false
      end

      {USet32.new(k1), true}
    end
  end

  # Returns a copy of this set without *value*.
  #
  # ```
  # set = Pf::USet32[1, 2, 3]
  #
  # set.delete(2) # => Pf::USet32[1, 3]
  # set           # => Pf::USet32[1, 2, 3]
  # ```
  def delete(value : UInt32) : USet32
    case k = @kernel
    in Empty    then self
    in Nonempty then USet32.new(USet.difference?(k, USet.path(value)) || Empty.new)
    end
  end

  # Union: returns a new set containing integers from this and *other* sets.
  #
  # ```
  # Pf::USet32[1, 2, 3] | Pf::USet32[4, 5, 6] # => Pf::USet32[1, 2, 3, 4, 5, 6]
  # ```
  def |(other : USet32) : USet32
    k0, k1 = @kernel, other.@kernel

    case {k0, k1}
    in {Empty, Empty}       then self
    in {Empty, Nonempty}    then other
    in {Nonempty, Empty}    then self
    in {Nonempty, Nonempty} then USet32.new(USet.union(k0, k1))
    end
  end

  # Alias of `|`.
  def +(other : USet32) : USet32
    self | other
  end

  # Intersection: returns a new set containing integers common to this and
  # *other* sets.
  #
  # ```
  # Pf::USet32[1, 2, 3] & Pf::USet32[2, 3, 4] # => Pf::USet32[2, 3]
  # ```
  def &(other : USet32) : USet32
    k0, k1 = @kernel, other.@kernel

    case {k0, k1}
    in {Empty, _}        then self
    in {Nonempty, Empty} then other
    in {Nonempty, Nonempty}
      USet32.new(USet.intersection?(k0, k1) || Empty.new)
    end
  end

  # Difference: returns a new set containing integers from this set that are
  # not in the *other* set.
  #
  # ```
  # Pf::USet32[1, 2, 3] - Pf::USet32[2, 3, 4] # => Pf::USet32[1]
  # ```
  def -(other : USet32) : USet32
    k0, k1 = @kernel, other.@kernel

    case {k0, k1}
    in {Empty, _}, {Nonempty, Empty}
      self
    in {Nonempty, Nonempty}
      USet32.new(USet.difference?(k0, k1) || Empty.new)
    end
  end

  def pretty_print(pp)
    pp.list("Pf::USet32[", self, "]")
  end

  def inspect(io)
    io << "Pf::USet32["
    join(io, ", ") { |el| el.inspect(io) }
    io << "]"
  end

  def to_s(io)
    inspect(io)
  end

  def ==(other : USet32) : Bool
    k0, k1 = @kernel, other.@kernel

    case {k0, k1}
    in {Empty, Empty}       then true
    in {Empty, Nonempty}    then false
    in {Nonempty, Empty}    then false
    in {Nonempty, Nonempty} then USet.equals?(k0, k1)
    end
  end

  def hash(hasher)
    case k = @kernel
    in Empty    then k.hash(hasher)
    in Nonempty then USet.hash(k, hasher)
    end
  end
end

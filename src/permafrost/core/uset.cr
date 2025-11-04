# :nodoc:
module Pf::Core::USet
  extend self

  def ptr(object : T) forall T
    objects = Pointer(T).malloc(1)
    objects.value = object
    objects
  end

  def bit_set?(bitset : Int, bit_index : Int) : Bool
    bitset.bit(bit_index) == 1
  end

  # Iteration order: LSB to MSB.
  #
  # Reference: https://lemire.me/blog/2018/02/21/iterating-over-set-bits-quickly/
  def each_set_bit(bitset : Int, &)
    loop do
      break if bitset.zero?

      t = bitset & &-bitset
      r = bitset.trailing_zeros_count
      yield r

      bitset ^= t
    end
  end

  alias Trie = Bitmap | Chunk | WideNode | Node0 | Node1 | Node2 | Node3

  record Bitmap, bits : UInt64

  # TODO: chunks exists so that we can do SIMD on bitmaps, but I don't know how
  # to do SIMD nor is there any tooling to do that in Crystal.
  record Chunk, children : Bitmap*, presence : UInt32, cardinality : UInt32 do
    def self.new(bitmap : Bitmap, presence : UInt32)
      new(USet.ptr(bitmap), presence, bitmap.bits.popcount.to_u32)
    end
  end

  record WideNode, children : Chunk*, presence : UInt32, cardinality : UInt32 do
    def self.new(chunk : Chunk, presence : UInt32)
      new(USet.ptr(chunk), presence, chunk.cardinality)
    end
  end

  record Node0, children : WideNode*, presence : UInt16, cardinality : UInt32 do
    def self.new(node : WideNode, presence : UInt16)
      new(USet.ptr(node), presence, node.cardinality)
    end
  end

  record Node1, children : Node0*, presence : UInt16, cardinality : UInt32 do
    def self.new(node : Node0, presence : UInt16)
      new(USet.ptr(node), presence, node.cardinality)
    end
  end

  record Node2, children : Node1*, presence : UInt16, cardinality : UInt32 do
    def self.new(node : Node1, presence : UInt16)
      new(USet.ptr(node), presence, node.cardinality)
    end
  end

  record Node3, children : Node2*, presence : UInt16, cardinality : UInt32 do
    def self.new(node : Node2, presence : UInt16)
      new(USet.ptr(node), presence, node.cardinality)
    end
  end

  def nth(node : ChunkP | WideNodeP | Node0P | Node1P | Node2P | Node3P, n)
    unless n.zero?
      raise IndexError.new
    end

    node.child
  end

  def nth(node, n)
    size = node.presence.popcount
    unless n < size
      raise IndexError.new
    end

    node.children[n]
  end

  def fetch(node, bit_index, &)
    selector = 1u32 << bit_index
    return unless (presence(node) & selector) == selector

    index = (presence(node) & (selector &- 1)).popcount
    yield nth(node, index)
  end

  def fetch(node, bit_index)
    fetch(node, bit_index) { |value| return value }

    raise IndexError.new
  end

  def set!(node, bit_index, &)
    selector = 1u32 << bit_index
    unless (node.presence & selector) == selector
      raise IndexError.new
    end

    index = (node.presence & (selector &- 1)).popcount
    child0 = node.children[index]
    child1 = yield child0
    node.children[index] = child1
    node.copy_with(cardinality: cardinality(node) - cardinality(child0) + cardinality(child1))
  end

  def each_child_with_bit_index(node, &)
    index = 0
    each_set_bit(node.presence) do |bit_index|
      yield node.children[index], bit_index
      index += 1
    end
  end

  def each_child_with_bit_index(node : ChunkP | WideNodeP | Node0P | Node1P | Node2P | Node3P, &)
    yield node.child, node.index.to_i
  end

  def each_child(node, &)
    size = node.presence.popcount
    size.times do |index|
      yield node.children[index]
    end
  end

  def eqcast(a, b, &)
    x = promote(a, b)
    y = promote(b, a)

    unless rank(x) == rank(y)
      raise ArgumentError.new
    end

    yield x, y
  end

  def promote(a, b)
    return a unless rank(a) < rank(b)

    8.times do
      a = promote(a)
      if rank(a) == rank(b)
        return a
      end
    end

    raise ArgumentError.new
  end

  def rank(s)
    case s
    in Bitmap, BitmapP     then 0
    in Chunk, ChunkP       then 1
    in WideNode, WideNodeP then 2
    in Node0, Node0P       then 3
    in Node1, Node1P       then 4
    in Node2, Node2P       then 5
    in Node3, Node3P       then 6
    end
  end

  def promote(s)
    case s
    in Bitmap    then Chunk.new(s, 1u32)
    in BitmapP   then ChunkP.new(s, 0u8)
    in Chunk     then WideNode.new(s, 1u32)
    in ChunkP    then WideNodeP.new(s, 0u8)
    in WideNode  then Node0.new(s, 1u32)
    in WideNodeP then Node0P.new(s, 0u8)
    in Node0     then Node1.new(s, 1u32)
    in Node0P    then Node1P.new(s, 0u8)
    in Node1     then Node2.new(s, 1u32)
    in Node1P    then Node2P.new(s, 0u8)
    in Node2     then Node3.new(s, 1u32)
    in Node2P    then Node3P.new(s, 0u8)
    in Node3, Node3P
      s
    end
  end

  alias TrieP = BitmapP | ChunkP | WideNodeP | Node0P | Node1P | Node2P | Node3P

  record BitmapP, index : UInt8
  record ChunkP, child : BitmapP, index : UInt8
  record WideNodeP, child : ChunkP, index : UInt8
  record Node0P, child : WideNodeP, index : UInt8
  record Node1P, child : Node0P, index : UInt8
  record Node2P, child : Node1P, index : UInt8
  record Node3P, child : Node2P, index : UInt8

  def presence(node : ChunkP | WideNodeP)
    1u32 << node.index
  end

  def presence(node : Node0P | Node1P | Node2P | Node3P)
    1u16 << node.index
  end

  def presence(node : Chunk | WideNode | Node0 | Node1 | Node2 | Node3)
    node.presence
  end

  def path(value : UInt32)
    # 6 LSB determine are the index in bitmap.
    root = BitmapP.new((value & 0x3f).to_u8)
    value >>= 6
    return root if value.zero?

    # 5 next bits are index in chunk.
    root = ChunkP.new(root, (value & 0x1f).to_u8)
    value >>= 5
    return root if value.zero?

    # 5 next bits are index of chunk in wide node.
    root = WideNodeP.new(root, (value & 0x1f).to_u8)
    value >>= 5
    return root if value.zero?

    root = Node0P.new(root, (value & 0xf).to_u8)
    value >>= 4
    return root if value.zero?

    root = Node1P.new(root, (value & 0xf).to_u8)
    value >>= 4
    return root if value.zero?

    root = Node2P.new(root, (value & 0xf).to_u8)
    value >>= 4
    return root if value.zero?

    root = Node3P.new(root, (value & 0xf).to_u8)
    value >>= 4

    root
  end

  def trie(node : Bitmap | Chunk | WideNode | Node0 | Node1 | Node2 | Node3)
    node
  end

  def trie(path : BitmapP)
    Bitmap.new(1u64 << path.index)
  end

  def trie(path : ChunkP)
    Chunk.new(trie(path.child), 1u32 << path.index)
  end

  def trie(path : WideNodeP)
    WideNode.new(trie(path.child), 1u32 << path.index)
  end

  def trie(path : Node0P)
    Node0.new(trie(path.child), 1u16 << path.index)
  end

  def trie(path : Node1P)
    Node1.new(trie(path.child), 1u16 << path.index)
  end

  def trie(path : Node2P)
    Node2.new(trie(path.child), 1u16 << path.index)
  end

  def trie(path : Node3P)
    Node3.new(trie(path.child), 1u16 << path.index)
  end

  def cardinality(s : Bitmap) : UInt32
    s.bits.popcount.to_u32
  end

  def cardinality(s : Chunk | WideNode | Node0 | Node1 | Node2 | Node3) : UInt32
    s.cardinality
  end

  def cardinality(s : TrieP) : UInt32
    1u32
  end

  def includes?(s : Bitmap, value : UInt32) : Bool
    # Forget bounds checks; `<<` will give us all zeros anyway in case
    # someone calls this directly with value > 63.
    s.bits & (1u64 << value) > 0
  end

  {% for row in { {Chunk, 6, 5}, {WideNode, 6 + 5*1, 5}, {Node0, 6 + 5*2, 4}, {Node1, 6 + 5*2 + 4*1, 4}, {Node2, 6 + 5*2 + 4*2, 4}, {Node3, 6 + 5*2 + 4*3, 4} } %}
    {% cls, offset, width = row %}

    def includes?(s : {{cls.id}}, value : UInt32)
      lo = value & {{ (1 << offset) - 1 }}
      value >>= {{offset}}

      hi = value & {{ (1 << width) - 1 }}
      value >>= {{width}}

      unless value.zero?
        return false
      end

      fetch(s, hi) { |sub| return includes?(sub, lo) }

      false
    end
  {% end %}

  def each(prefix : UInt32, s : Bitmap, &) : Nil
    each_set_bit(s.bits) do |value|
      yield (prefix << 6) | value
    end
  end

  def each(prefix : UInt32, s : Chunk | WideNode, &) : Nil
    each_child_with_bit_index(s) do |bitmap, bit_index|
      each((prefix << 5) | bit_index, bitmap) do |value|
        yield value
      end
    end
  end

  def each(prefix : UInt32, s : Node0 | Node1 | Node2 | Node3, &) : Nil
    each_child_with_bit_index(s) do |bitmap, bit_index|
      each((prefix << 4) | bit_index, bitmap) do |value|
        yield value
      end
    end
  end

  def intersects?(s0 : Bitmap, s1 : Bitmap) : Bool
    !(s0.bits & s1.bits).zero?
  end

  def intersects?(s0 : Bitmap, s1 : BitmapP) : Bool
    intersects?(s0, trie(s1))
  end

  {% for cls in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    def intersects?(s0 : {{cls.id}}, s1 : {{cls.id}} | {{cls.id}}P) : Bool
      common = presence(s0) & presence(s1)
      if common.zero?
        return false
      end

      if s1.is_a?({{cls.id}}) && s0.children == s1.children
        return true
      end

      each_set_bit(common) do |bit_index|
        x = fetch(s0, bit_index)
        y = fetch(s1, bit_index)
        if intersects?(x, y)
          return true
        end
      end

      false
    end
  {% end %}

  def intersects?(s0, s1) : Bool
    eqcast(s0, s1) { |x, y| intersects?(x, y) }
  end

  def subset?(lg : Bitmap, sm : Bitmap) : Bool
    (lg.bits & sm.bits) == sm.bits
  end

  def subset?(lg : Bitmap, sm : BitmapP) : Bool
    subset?(lg, trie(sm))
  end

  {% for cls in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    def subset?(lg : {{cls.id}}, sm : {{cls.id}} | {{cls.id}}P) : Bool
      # All bits must be set.
      unless (presence(lg) & presence(sm)) == presence(sm)
        return false
      end

      # Cardinality must be proper.
      if cardinality(sm) > cardinality(lg)
        return false
      end

      each_child_with_bit_index(sm) do |child, bit_index|
        next unless subset?(fetch(lg, bit_index), child)
        return true
      end

      false
    end
  {% end %}

  def subset?(lg, sm)
    eqcast(lg, sm) { |x, y| subset?(x, y) }
  end

  def union(s0 : Bitmap, s1 : Bitmap) : Bitmap
    Bitmap.new(s0.bits | s1.bits)
  end

  def union(s0 : Bitmap, s1 : BitmapP) : Bitmap
    Bitmap.new(s0.bits | (1u64 << s1.index))
  end

  {% for cls, i in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    {% childcls = %w(Bitmap Chunk WideNode Node0 Node1 Node2)[i] %}

    def union(s0 : {{cls.id}}, s1 : {{cls.id}} | {{cls.id}}P)
      s0p = presence(s0)
      s1p = presence(s1)
      mix = s0p | s1p

      # If mix is unchanged, there is the possibility that s1 is already in s0.
      # Check using `subset?` to avoid malloc. Subset is relatively cheap. Either
      # it's going to be deep and chase-y but we won't allocate -- in the positive
      # case. Or it's going to exit early, after presence/cardinality checks -- in
      # the very negative case (subsets differ greatly below). In the mid case, if
      # some subsets are shared and others aren't, we'd still avoid allocations in
      # the end, so that's a win.
      if mix == s0p && subset?(s0, s1)
        return s0
      end

      mem = Pointer({{childcls.id}}).malloc(mix.popcount)

      l = i = j = 0
      cardinality = 0u32

      each_set_bit(mix) do |index|
        x = bit_set?(s0p, index)
        y = bit_set?(s1p, index)

        if x && y
          mem[l] = u = union(nth(s0, i), nth(s1, j))
          cardinality += cardinality(u)
          i += 1
          j += 1
          l += 1
        elsif x
          mem[l] = u = nth(s0, i)
          cardinality += cardinality(u)
          i += 1
          l += 1
        elsif y
          mem[l] = u = trie(nth(s1, j))
          cardinality += cardinality(u)
          j += 1
          l += 1
        end
      end

      {{cls.id}}.new(mem, mix, cardinality)
    end
  {% end %}

  def union(s0, s1)
    eqcast(s0, s1) { |x, y| union(x, y) }
  end

  def union!(s0 : Bitmap, s1 : Bitmap | BitmapP)
    union(s0, s1)
  end

  {% for cls, i in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    {% childcls = %w(Bitmap Chunk WideNode Node0 Node1 Node2)[i] %}

    def union!(s0 : {{cls.id}}, s1 : {{cls.id}} | {{cls.id}}P)
      mix = presence(s0) | presence(s1)

      # If s1 adds nothing to s0, then simply assign in-place.
      if mix == presence(s0)
        each_child_with_bit_index(s1) do |b, bit_index|
          s0 = set!(s0, bit_index) { |a| union!(a, b) }
        end
        return s0
      end

      # If s1 adds to s0, union the old way; it's not going to make that much
      # of a difference. Make sure however to call the mutable version on children.

      mem = Pointer({{childcls.id}}).malloc(mix.popcount)

      l = i = j = 0
      cardinality = 0u32

      s0p = presence(s0)
      s1p = presence(s1)

      each_set_bit(mix) do |index|
        x = bit_set?(s0p, index)
        y = bit_set?(s1p, index)

        if x && y
          mem[l] = u = union!(nth(s0, i), nth(s1, j))
          cardinality += cardinality(u)
          i += 1
          j += 1
          l += 1
        elsif x
          mem[l] = u = nth(s0, i)
          cardinality += cardinality(u)
          i += 1
          l += 1
        elsif y
          mem[l] = u = trie(nth(s1, j))
          cardinality += cardinality(u)
          j += 1
          l += 1
        end
      end

      {{cls.id}}.new(mem, mix, cardinality)
    end
  {% end %}

  def union!(s0, s1)
    eqcast(s0, s1) { |x, y| union!(x, y) }
  end

  def intersection?(s0 : Bitmap, s1 : Bitmap)
    bits = s0.bits & s1.bits
    bits.zero? ? nil : Bitmap.new(bits)
  end

  def intersection?(s0 : Bitmap, s1 : BitmapP)
    intersection?(s0, trie(s1))
  end

  {% for cls, i in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    {% childcls = %w(Bitmap Chunk WideNode Node0 Node1 Node2)[i] %}
    {% branches = [32, 32, 16, 16, 16, 16][i] %}

    def intersection?(s0 : {{cls.id}}, s1 : {{cls.id}} | {{cls.id}}P)
      common = presence(s0) & presence(s1)
      return if common.zero?

      if s1.is_a?({{cls.id}}) && s0.children == s1.children
        return s0
      end

      mem = Pointer({{childcls.id}}).null
      top = 0
      skipped = 0
      presence = 0u{{branches}}
      cardinality = 0u32

      each_set_bit(common) do |bit_index|
        x = fetch(s0, bit_index)
        y = fetch(s1, bit_index)
        unless ix = intersection?(x, y)
          skipped += 1
          next
        end

        unless mem
          # We may skip stuff ahead as well but nah, we're doing better than
          # an upfront malloc() anyway; we don't have to be too smart.
          mem = Pointer({{childcls.id}}).malloc(common.popcount - skipped)
        end

        mem[top] = ix
        top += 1
        presence |= 1u{{branches}} << bit_index
        cardinality += cardinality(ix)
      end

      mem ? {{cls.id}}.new(mem, presence, cardinality) : nil
    end
  {% end %}

  def intersection?(s0, s1)
    eqcast(s0, s1) { |x, y| intersection?(x, y) }
  end

  def difference?(s0 : Bitmap, s1 : Bitmap)
    bits = s0.bits & ~s1.bits
    bits.zero? ? nil : Bitmap.new(bits)
  end

  def difference?(s0 : Bitmap, s1 : BitmapP)
    difference?(s0, trie(s1))
  end

  {% for cls, i in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    {% childcls = %w(Bitmap Chunk WideNode Node0 Node1 Node2)[i] %}
    {% branches = [32, 32, 16, 16, 16, 16][i] %}

    def difference?(s0 : {{cls.id}}, s1 : {{cls.id}} | {{cls.id}}P)
      mem = Pointer({{childcls.id}}).null
      top = 0
      skipped = 0
      presence = 0u{{branches}}
      cardinality = 0u32

      each_set_bit(presence(s0)) do |bit_index|
        x0 = fetch(s0, bit_index)

        if bit_set?(presence(s1), bit_index)
          # Subtract common recursively.
          unless x1 = difference?(x0, fetch(s1, bit_index))
            skipped += 1
            next
          end
        else
          # Copy unique to s0.
          x1 = x0
        end

        unless mem
          mem = Pointer({{childcls.id}}).malloc(presence(s0).popcount - skipped)
        end

        mem[top] = x1
        top += 1
        presence |= 1u{{branches}} << bit_index
        cardinality += cardinality(x1)
      end

      mem ? {{cls.id}}.new(mem, presence, cardinality) : nil
    end
  {% end %}

  def difference?(s0, s1)
    eqcast(s0, s1) { |x, y| difference?(x, y) }
  end

  # def xor(s0 : Bitmap, s1 : Bitmap) : Bitmap
  # end

  def equals?(s0 : Bitmap, s1 : Bitmap) : Bool
    s0.bits == s1.bits
  end

  def equals?(s0 : Bitmap, s1 : BitmapP) : Bool
    s0.bits == (1u64 << s1.index)
  end

  {% for cls in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    def equals?(s0 : {{cls.id}}, s1 : {{cls.id}} | {{cls.id}}P)
      return false unless presence(s0) == presence(s1)

      # Pointer equality. Since we're doing structural sharing, this could be
      # hit at some point and is thus a useful fast path.
      if s1.is_a?({{cls.id}}) && s0.children == s1.children
        return true
      end

      return false unless cardinality(s0) == cardinality(s1)

      index = 0
      each_child(s0) do |a|
        b = nth(s1, index)
        return false unless equals?(a, b)

        index += 1
      end

      true
    end
  {% end %}

  def equals?(s0, s1) : Bool
    eqcast(s0, s1) { |x, y| equals?(x, y) }
  end

  def hash(s : Bitmap, hasher)
    s.bits.hash(hasher)
  end

  {% for cls in %w(Chunk WideNode Node0 Node1 Node2 Node3) %}
    def hash(s : {{cls.id}}, hasher)
      each_child(s) do |child|
        hasher = hash(child, hasher)
      end
      hasher
    end
  {% end %}
end

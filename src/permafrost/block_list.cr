module Pf
  # :nodoc:
  struct Block8(T)
    include Indexable(T)

    TAG_MASK = 0b111u64

    def initialize(@bits : T*)
    end

    def self.new(objects : T*, size : Int32)
      Kit.assert 1 <= size <= 8
      Kit.assert (objects.address & TAG_MASK) == 0u64

      new(Pointer(T).new(objects.address | (size - 1).to_u64))
    end

    def self.new
      new(Pointer(T).null)
    end

    def objects : T*
      Pointer(T).new(@bits.address & ~TAG_MASK)
    end

    def size : Int32
      if @bits.null?
        return 0
      end

      (@bits.address & TAG_MASK).to_i + 1
    end

    def unsafe_fetch(index : Int) : T
      objects[index]
    end

    def append?(object : T) : Block8(T)?
      return unless size < 8

      target = Pointer(T).malloc(size + 1)
      target.copy_from(objects, size)
      target[size] = object

      Block8.new(target, size + 1)
    end

    def prior : Block8(T)
      Kit.assert size > 0

      if size == 1
        return Block8(T).new
      end

      Block8.new(objects, size - 1)
    end

    def pretty_print(pp)
      pp.list("Block8[", self, "]")
    end

    def ==(other : Block8) : Bool
      return true if @bits == other.@bits

      equals?(other) { |a, b| a == b }
    end

    # Indexable#hash(hasher)
  end

  # A simple persistent linked list of blocks, storing at most 8x *T*s per block.
  # The block that you append to is copied wholesale, which is usually cheap enough
  # while giving you semi-bearable locality during iteration (e.g. if *T* is pointer-
  # sized, you get 64-byte blocks which are in theory big friends with the CPU, but
  # let me not make myself sound like I understand what I'm talking about here!)
  class BlockList(T)
    include Enumerable(T)

    # Returns the number of elements in this list.
    getter size : Int32

    # :nodoc:
    def initialize(@size : Int32, @blks : BlockList(T)?, @blk : Block8(T))
    end

    # Constructs an empty block list.
    def self.new : BlockList(T)
      new(size: 0, blks: nil, blk: Block8(T).new)
    end

    # Constructs a block list containing *objects*.
    def self.[](*objects)
      objects.reduce(BlockList(typeof(Enumerable.element_type(objects))).new) do |memo, object|
        memo.append(object)
      end
    end

    # :nodoc:
    def reverse_each_block(& : Block8(T) ->)
      current = self
      while current
        yield current.@blk
        current = current.@blks
      end
    end

    # :nodoc:
    EACH_BLOCK_STACKALLOC = 16 # x blocks

    # :nodoc:
    def each_block(& : Block8(T) ->)
      blksize, rem = @size.divmod(8)
      blksize += (rem > 0 ? 1 : 0)

      if blksize > EACH_BLOCK_STACKALLOC
        bufferptr = Pointer(Block8(T)).malloc(blksize)
      else
        buffer = uninitialized Block8(T)[EACH_BLOCK_STACKALLOC]
        bufferptr = buffer.to_unsafe
      end

      blkcnt = 0
      reverse_each_block do |block|
        bufferptr[blkcnt] = block
        blkcnt += 1
      end

      Kit.assert blksize == blkcnt

      blocks = bufferptr.to_slice(blkcnt)
      blocks.reverse_each { |block| yield block }
    end

    # Like `includes?`, but faster for `BlockList` in particular since it iterates
    # in memory-order (using `reverse_each`) vs. Enumerable's `includes?` which
    # uses `each`.
    def rincludes?(object needle) : Bool
      reverse_each do |object|
        return true if object == needle
      end

      false
    end

    # Yields elements in this list in front-to-back order.
    #
    # This method may allocate some buffer memory because it must reverse
    # the list to yield elements in the correct order.
    #
    # NOTE: All `Enumerable` methods eventually end up calling this method,
    # so you must evaluate the costs (if that matters to you!)
    def each(& : T ->) : Nil
      each_block do |block|
        block.each { |object| yield object }
      end
    end

    # Yields elements in this list in back-to-front order.
    #
    # Note that this is the memory order of `BlockList`, so this method is
    # a pure traversal (compared to e.g. `each`, which does additional work
    # to give you elements in expected order).
    def reverse_each(& : T ->) : Nil
      reverse_each_block do |block|
        block.reverse_each { |object| yield object }
      end
    end

    # See `Indexable#fetch(index : Int, &)`.
    def fetch(index : Int, &)
      index += @size if index < 0
      unless 0 <= index < @size
        return yield
      end

      rbound = @size

      reverse_each_block do |block|
        lbound = rbound - block.size
        if lbound <= index < rbound
          return block.unsafe_fetch(index - lbound)
        end

        rbound -= block.size
      end

      yield
    end

    # See `Indexable#[]?`.
    def []?(index : Int) : T?
      fetch(index) { }
    end

    # See `Indexable#[]`.
    def [](index : Int) : T
      fetch(index) { raise IndexError.new }
    end

    # Inserts *object* at the back of this list.
    def append(object : T) : BlockList(T)
      if blk1 = @blk.append?(object)
        return BlockList.new(@size + 1, @blks, blk1)
      end

      Kit.assert blk1 = Block8(T).new.append?(object)

      BlockList.new(@size + 1, self, blk1)
    end

    # Returns the part of this list before the last element. If this list is
    # empty, returns an empty list.
    def prior : BlockList(T)
      if @size.zero?
        Kit.assert @blks.nil?
        Kit.assert @blk.empty?
        return self
      end

      if @blk.size == 1
        return @blks || BlockList(T).new
      end

      BlockList.new(@size - 1, @blks, @blk.prior)
    end

    # Returns the last element in this list, or `nil` if this list is empty.
    def last? : T?
      @blk.last { }
    end

    # Returns the last element in this list. Raises `IndexError` if this
    # list is empty.
    def last : T
      @blk.last { raise IndexError.new }
    end

    def pretty_print(pp)
      pp.list("BlockList[", self, "]")
    end

    # Returns `true` if this list is equal to *other*.
    def ==(other : BlockList(T)) : Bool
      return true if same?(other)
      return false unless size == other.size
      return false unless @blk == other.@blk

      if same?(prior) # We have no prior.
        # Equality depends on whether other has no prior, too.
        return other.same?(other.prior)
      end

      prior == other.prior
    end

    def hash(hasher)
      {BlockList, @blk, same?(prior) ? nil : prior}.hash(hasher)
    end
  end
end

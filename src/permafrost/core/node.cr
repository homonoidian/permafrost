module Pf::Core
  alias AuthorId = UInt32

  AUTHOR_NONE  = AuthorId.new(0)
  AUTHOR_FIRST = AUTHOR_NONE + 1

  # Includers can look up a stored value in the trie.
  module IProbeFetch(T)
    # Returns the full path to the stored value (usually the stored value's hash).
    abstract def path : UInt64

    # Returns `true` if this probe accepts the given stored value.
    abstract def match?(stored : T) : Bool
  end

  # Includers can author a change in the trie, enabling them to later mutate
  # the part of the trie they've already copied. See `author`.
  module IProbeAuthored
    # Returns the id of the author of the proposed addition. The author is made
    # the owner of the path-copied items and children arrays in the trie. Meaning
    # further changes along the same route *made by the same author* will not produce
    # copies; the author's done the job already.
    #
    # Essentially `author` is the "password" for mutating the resulting part of the trie.
    # Completely new nodes give write access to both arrays to `author` immediately.
    #
    # The id must be unique across distinct edits of the trie (this is guaranteed
    # by `Pf::Map::Commit` and `Pf::Set::Commit`; they are the main users of this
    # feature). By using the analogy defined above, if more than one entity knows
    # the password to edit the trie in-place, everything about immutability
    # or exclusive write access is broken.
    #
    # We never make full copies of the trie, not at the beginning, nor at the end.
    # We only make copies of edited paths. When the edit sequence finishes, its
    # author must be guaranteed to retire, as the trie is passed to the immutable
    # interface as-is. So if the author does not retire and modifies the tree,
    # the immutable version will change as well, which is not expected.
    #
    # If unavailable, you can return `AUTHOR_NONE`.
    abstract def author : AuthorId
  end

  # Includers can add stored values to the trie, or replace them.
  module IProbeAdd(T)
    include IProbeFetch(T)
    include IProbeAuthored

    # Returns the value associated with this probe, to be stored in `Node`.
    abstract def value : T

    # Returns `true` if an existing *stored* value should be replaced with
    # this probe's own `value`.
    abstract def replace?(stored : T) : Bool
  end

  # Includers can remove stored values from the trie.
  module IProbeDelete(T)
    include IProbeFetch(T)
    include IProbeAuthored
  end

  # Represents a trie node.
  #
  # Instances of *T* are stored inline. Meaning if *T* is a large struct lots and lots
  # of bytes are going to be copied, mostly unnecessarily. Clients will probably want
  # to catch large value *T*s and wrap them in a pointer. The notion of "large" depends
  # on the client. It could be an interface or could be a sizeof threshold.
  class Node(T)
    private WINDOW      = 0x1fu32
    private WINDOW_SIZE =       5

    def initialize(
      @items = Sparse32(T).new,
      @children = Sparse32(Node(T)).new,
      @beneath = 0,
      @itemsof = AUTHOR_NONE,
      @childrenof = AUTHOR_NONE
    )
    end

    # Returns `true` if the current items array belongs to *author*.
    private def items_belong_to?(author : AuthorId) : Bool
      @itemsof == author && author != AUTHOR_NONE
    end

    # Returns `true` if the current children array belongs to *author*.
    private def children_belong_to?(author : AuthorId)
      @childrenof == author && author != AUTHOR_NONE
    end

    # Mutably or immutably shifts the number of beneath items by *delta*.
    # Beneath is conceptually grouped with children. Its mutability or
    # immutability depends on whether the children are owned by *author*.
    private def modify(*, author : AuthorId, delta : Int) : Node(T)
      return self if delta.zero? # Let the caller be careless.

      if children_belong_to?(author)
        @beneath += delta
        self
      else
        # We do not actually make a copy of children here; there's no need to (huh?)
        # But we must make sure the node itself is copied.
        Node(T).new(@items, @children, @beneath + delta, @itemsof, author)
      end
    end

    # Mutably or immutably (depending on *author*) modifies the *item* or *child*
    # at the given *index*.
    private def modify(*, at index : Int, item : {T}?, author : AuthorId)
      if items_belong_to?(author)
        @items = item ? @items.with!(index, item[0]) : @items.without!(index)
        self
      else
        Node(T).new(item ? @items.with(index, item[0]) : @items.without(index), @children, @beneath, author, @childrenof)
      end
    end

    # :ditto:
    private def modify(*, at index : Int, child : Node(T)?, author : AuthorId, delta : Int)
      if children_belong_to?(author)
        @beneath += delta
        @children = child ? @children.with!(index, child) : @children.without!(index)
        self
      else
        Node(T).new(@items, child ? @children.with(index, child) : @children.without(index), @beneath + delta, @itemsof, author)
      end
    end

    # Returns `true` if this node holds no items and points to no children.
    def empty? : Bool
      @items.empty? && @children.empty?
    end

    # Returns the number of items in this node and all nodes beneath.
    def size : Int32
      @items.size + @beneath
    end

    # Returns *n*-th item in this node or in one of the nodes beneath.
    #
    # The order of items is the same as in `each`.
    def nth?(n : Int32) : T?
      return if n < 0

      if n < @items.size
        return @items.to_unsafe[n]
      end

      n &-= @items.size

      @children.each do |child|
        return child.nth?(n) if n.in?(0...child.size)
        return if n < child.size
        n &-= child.size
      end
    end

    # Yields each item from this node and from all child nodes.
    def each(& : T ->) : Nil
      # Lower part of the iteration stack -- use stack space.
      lower = uninitialized self[128]
      lower[0] = self

      # Upper part of the iteration stack -- use heap space (array) on demand.
      # It would be really really hard to hit this, unless the hash function
      # produces a lot (a lot!) of collisions or the number of elements
      # is astronomical.
      upper = nil

      sp = 1 # < stack pointer

      while sp > 0
        # Pop node
        sp &-= 1
        lo = sp < lower.size
        node = lo ? lower.unsafe_fetch(sp) : upper.not_nil!.unsafe_fetch(sp - lower.size)

        # Yield items.
        node.@items.each { |item| yield item }

        # Fast path: all children fit into lower.
        if sp + node.@children.size < lower.size
          node.@children.reverse_each do |child|
            lower.unsafe_put(sp, child)
            sp &+= 1
          end
          next
        end

        # Slow (ish) path.
        node.@children.reverse_each do |child|
          if lo
            lower.unsafe_put(sp, child)
          else
            upper ||= [] of self
            index = sp - lower.size
            if index < upper.size
              upper.unsafe_put(index, child)
            else
              upper.push(child)
            end
          end

          sp &+= 1
          lo = sp < lower.size
        end
      end
    end

    # Retrieves the stored value that is accepted by *probe*. Returns the first
    # stored value accepted by *probe*, or `nil` if *probe* accepted no values.
    #
    # The returned value is wrapped in a tuple to differentiate between `nil`
    # as value and `nil` as absence.
    def fetch?(probe : IProbeFetch(T)) : {T}?
      fetch?(probe, path: probe.path)
    end

    # Updates or inserts the stored value accepted by *probe*.
    #
    # Returns a tuple where the first element is a boolean indicating whether
    # the amount of elements in the trie increased by one, and the second element
    # is the modified version of `self`.
    #
    # If *probe* wishes mutation, the second element is exactly `self` (and the
    # first element still indicates whether the size increased).
    #
    # If no changes were made (the stored value is the same as that of *probe*)
    # the second element is also exactly `self` (and the first element is `false`).
    def add(probe : IProbeAdd(T)) : {Bool, Node(T)}
      add(probe, path: probe.path)
    end

    # Removes the stored value accepted by *probe*. Returns a tuple where the first
    # element is a boolean indicating whether the amount of elements in the trie
    # decreased by one, and the second element is the modified version of `self`.
    #
    # If *probe* wishes mutation, the second element is exactly `self`. If no changes
    # were made (nothing was removed), the second element is also exactly `self`.
    def delete(probe : IProbeDelete(T)) : {Bool, Node(T)}
      delete(probe, path: probe.path)
    end

    protected def fetch?(probe : IProbeFetch, path : UInt64) : {T}?
      node = self

      while true
        index = path & WINDOW
        item = node.@items.at?(index)
        return {item} if item && probe.match?(item)
        return unless node = node.@children.at?(index)
        path >>= WINDOW_SIZE
      end
    end

    protected def add(probe : IProbeAdd(T), path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW

      item = @items.at?(index)
      if item && probe.match?(item)
        # If probe matched and wants to replace the item, replace it. Otherwise
        # we're done, no change. Since we're replacing, not adding the item,
        # hence we return `false` as the number of items didn't change.
        return false, self unless probe.replace?(item)
        return false, modify(at: index, item: {probe.value}, author: probe.author)
      end

      child0 = @children.at?(index)

      if child0 # Child exists, proceed deeper.
        added, child1 = child0.add(probe, path >> WINDOW_SIZE)
        if child0.same?(child1)
          return added, modify(author: probe.author, delta: added ? 1 : 0)
        end
        return added, modify(at: index, child: child1, author: probe.author, delta: added ? 1 : 0)
      end

      if item.nil? # Child doesn't exist and item slot is unoccupied.
        return true, modify(at: index, item: {probe.value}, author: probe.author)
      end

      # Child does not exist and item slot is occupied. Create a child.
      child0 = Node(T).new(itemsof: probe.author, childrenof: probe.author)
      added, child1 = child0.add(probe, path >> WINDOW_SIZE)

      {added, modify(at: index, child: child1, author: probe.author, delta: added ? 1 : 0)}
    end

    protected def delete(probe : IProbeDelete, path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW

      item = @items.at?(index)
      if item && probe.match?(item)
        return true, modify(at: index, item: nil, author: probe.author)
      end

      # If child cannot be found indicate no change.
      unless child = @children.at?(index)
        return false, self
      end

      removed, child = child.delete(probe, path >> WINDOW_SIZE)
      return false, self unless removed

      {true, modify(at: index, child: child.empty? ? nil : child, author: probe.author, delta: -1)}
    end
  end
end

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
  # of bytes are going to be copied, mostly unnecessarily. Callers will probably want
  # to catch large value *T*s and wrap them in a pointer. The notion of "large" depends
  # on the caller. It could be an interface or could be a sizeof threshold.
  class Node(T)
    private WINDOW      = 0x1fu32
    private WINDOW_SIZE =       5

    def initialize(
      @items = Sparse32(T).new,
      @children = Sparse32(Node(T)).new,
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

    # Mutably or immutably (depending on *author*) modifies the *item* or *child*
    # at the given *index*.
    private def modify(*, at index : Int, item : {T}?, author : AuthorId)
      if items_belong_to?(author)
        @items = item ? @items.with!(index, item[0]) : @items.without!(index)
        self
      else
        Node(T).new(item ? @items.with(index, item[0]) : @items.without(index), @children, author, @childrenof)
      end
    end

    # :ditto:
    private def modify(*, at index : Int, child : Node(T)?, author : AuthorId)
      if children_belong_to?(author)
        @children = child ? @children.with!(index, child) : @children.without!(index)
        self
      else
        Node(T).new(@items, child ? @children.with(index, child) : @children.without(index), @itemsof, author)
      end
    end

    # Returns `true` if this node holds no items and points to no children.
    def empty? : Bool
      @items.empty? && @children.empty?
    end

    # Yields each item from this node and from all child nodes.
    def each(& : T ->) : Nil
      stack = Array(self).new(@children.size + 1)
      stack.push(self)

      until stack.empty?
        node = stack.pop
        node.@items.each do |item|
          yield item
        end
        node.@children.each do |child|
          stack.push(child)
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

      # Item does not exist. Add it.
      unless item = @items.at?(index)
        return true, modify(at: index, item: {probe.value}, author: probe.author)
      end

      # Probe matched and wants to replace the item. We're replacing, not adding
      # the item, hence return `false` as the number of items didn't change.
      matches = probe.match?(item)
      if matches && probe.replace?(item)
        return false, modify(at: index, item: {probe.value}, author: probe.author)
      end

      # Probe matched but doesn't want to replace the item -- we're done,
      # no change.
      return false, self if matches

      # Child does not exist.
      unless child = @children.at?(index)
        _, child = Node(T)
          .new(itemsof: probe.author, childrenof: probe.author)
          .add(probe, path >> WINDOW_SIZE)

        return true, modify(at: index, child: child, author: probe.author)
      end

      added, newchild = child.add(probe, path >> WINDOW_SIZE)

      # Child exists, remains the same after addition.
      return added, self if child.same?(newchild)

      {added, modify(at: index, child: newchild, author: probe.author)}
    end

    protected def delete(probe : IProbeDelete, path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW
      item = @items.at?(index)

      if item && probe.match?(item)
        return true, modify(at: index, item: nil, author: probe.author)
      end

      # If child cannot be found indicate no change.
      return false, self unless child = @children.at?(index)

      removed, child = child.delete(probe, path >> WINDOW_SIZE)
      return false, self unless removed

      {true, modify(at: index, child: child.empty? ? nil : child, author: probe.author)}
    end
  end
end

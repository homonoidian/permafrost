module Pf::Core
  alias AuthorId = UInt64

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
  class Node(T)
    private WINDOW      = 0x1fu32
    private WINDOW_SIZE =       5

    # Represents the bitmap for the items and children arrays.
    #
    # ```text
    # BITMAP  = BMP_ITEMS BMP_CHILDREN
    # --------  --------- ------------
    # 64 bits    32 bits     32 bits
    # ```
    private struct Bitmap
      getter bits : UInt64

      def initialize(@bits : UInt64)
      end

      def items : UInt32
        (@bits >> 32u64).unsafe_as(UInt32)
      end

      def children : UInt32
        @bits.unsafe_as(UInt32)
      end

      def items=(items : UInt32)
        @bits = (items.unsafe_as(UInt64) << 32) | @bits.unsafe_as(UInt32)
      end

      def children=(children : UInt32)
        @bits = ((@bits >> 32) << 32) | children
      end
    end

    def initialize(@items = Pointer(T).null, @children = Pointer(Node(T)).null, @bitmap = 0u64, @writer_items = AUTHOR_NONE, @writer_children = AUTHOR_NONE)
    end

    # Returns the `Bitmap` for the items and children arrays.
    private def bitmap : Bitmap
      Bitmap.new(@bitmap)
    end

    # Returns the items array.
    protected def items : Sparse32
      Sparse32.new(@items, bitmap.items)
    end

    # Returns the children array.
    protected def children : Sparse32
      Sparse32.new(@children, bitmap.children)
    end

    # Updates the items array to *array*.
    protected def items=(array) : self
      bmp = bitmap
      bmp.items = array.bitmap
      @items = array.to_unsafe
      @bitmap = bmp.bits
      self
    end

    # Updates the children array to *array*.
    protected def children=(array) : self
      bmp = bitmap
      bmp.children = array.bitmap
      @children = array.to_unsafe
      @bitmap = bmp.bits
      self
    end

    # Returns a new `Node` where the items array and its writer are changed to
    # the values provided in the arguments.
    protected def change(*, items : Sparse32, writer : AuthorId) : Node(T)
      bmp = bitmap
      bmp.items = items.bitmap

      Node.new(items.to_unsafe, @children, bmp.bits, writer, @writer_children)
    end

    # Returns a new `Node` where the children array and its writer are changed to
    # the values provided in the arguments.
    protected def change(*, children : Sparse32, writer : AuthorId) : Node(T)
      bmp = bitmap
      bmp.children = children.bitmap

      Node.new(@items, children.to_unsafe, bmp.bits, @writer_items, writer)
    end

    # Returns `true` if this node holds no items and points to no children.
    def empty? : Bool
      @bitmap.zero?
    end

    # Yields each item from this node and from all child nodes.
    def each(& : T ->) : Nil
      stack = Array(self).new(children.size + 1)
      stack.push(self)

      until stack.empty?
        node = stack.pop
        node.items.each do |item|
          yield item
        end
        node.children.each do |child|
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
        item = node.items.at?(index)
        return {item} if item && probe.match?(item)
        return unless node = node.children.at?(index)
        path >>= WINDOW_SIZE
      end
    end

    protected def add(probe : IProbeAdd(T), path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW
      items = self.items
      item = items.at?(index)

      if item.nil? || (accepted = probe.match?(item)) && (replaced = probe.replace?(item))
        if probe.author != AUTHOR_NONE && @writer_items == probe.author
          self.items = items.with!(index, probe.value)
          return replaced != true, self
        end
        return replaced != true, change(items: items.with(index, probe.value), writer: probe.author)
      end

      return false, self if accepted

      children = self.children

      if child = children.at?(index)
        created = false
      else
        child = Node(T).new(writer_items: probe.author, writer_children: probe.author)
        created = true
      end

      added, newchild = child.add(probe, path >> WINDOW_SIZE)
      return added, self if !created && child.same?(newchild)

      if probe.author != AUTHOR_NONE && @writer_children == probe.author
        self.children = children.with!(index, newchild)
        {added, self}
      else
        newchildren = children.with(index, newchild)
        {added, change(children: newchildren, writer: probe.author)}
      end
    end

    protected def delete(probe : IProbeDelete, path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW
      items = self.items
      item = items.at?(index)

      if item && probe.match?(item)
        if probe.author != AUTHOR_NONE && @writer_items == probe.author
          self.items = items.without!(index)
          return true, self
        end
        return true, change(items: items.without(index), writer: probe.author)
      end

      children = self.children

      return false, self unless child = children.at?(index)

      removed, newchild = child.delete(probe, path >> WINDOW_SIZE)
      return removed, self if child.same?(newchild)

      if newchild.empty?
        if probe.author != AUTHOR_NONE && @writer_children == probe.author
          self.children = children.without!(index)
          return removed, self
        end
        newchildren = children.without(index)
      else
        if probe.author != AUTHOR_NONE && @writer_children == probe.author
          self.children = children.with!(index, newchild)
          return removed, self
        end
        newchildren = children.with(index, newchild)
      end

      {removed, change(children: newchildren, writer: probe.author)}
    end
  end
end

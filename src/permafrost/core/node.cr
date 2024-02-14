module Pf::Core
  alias AuthorId = UInt64

  module IProbeAt
    # Returns the full path to the stored value (usually the stored value's hash).
    abstract def path : UInt64

    # Returns `true` if this probe accepts the given stored value.
    abstract def match?(stored) : Bool
  end

  module IProbeAdd(T)
    include IProbeAt

    # Returns the value associated with this probe, to be stored in `Node`.
    abstract def value : T

    abstract def author? : AuthorId?
    abstract def replace?(stored : T) : Bool
  end

  module IProbeDelete
    include IProbeAt

    abstract def author? : AuthorId?
  end

  # Represents a trie node.
  class Node(T)
    private WINDOW      = 0x1fu32
    private WINDOW_SIZE =       5

    def initialize(@items = Sparse32(T).new, @children = Sparse32(Node(T)).new, @writer_items : AuthorId? = nil, @writer_children : AuthorId? = nil)
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

    # :nodoc:
    def at?(probe : IProbeAt, path : UInt64) : {T}?
      index = path & WINDOW
      item = @items.at?(index)
      return {item} if item && probe.match?(item)
      return unless child = @children.at?(index)

      child.at?(probe, path >> WINDOW_SIZE)
    end

    # Retrieves the stored value that is accepted by *probe*. Returns the first
    # stored value accepted by *probe*, or `nil` if *probe* accepted no values.
    def at?(probe : IProbeAt) : {T}?
      at?(probe, path: probe.path)
    end

    # Updates or inserts the value of *probe*. Returns a tuple where the first element
    # is a boolean indicating whether the value was stored, and the second element is
    # the resulting `Node`.
    #
    # If *probe* wishes mutation, the resulting node is `self`. If no changes were
    # made (the stored value is the same as that of *probe*) the resulting node
    # is also `self`.
    def with(probe : IProbeAdd(T)) : {Bool, Node(T)}
      self.with(probe, path: probe.path)
    end

    # Removes the stored value accepted by *probe*. Returns a tuple where the first
    # element is a boolean indicating whether the value was removed, and the second
    # element is the resulting `Node`.
    #
    # If *probe* wishes mutation, the resulting node is `self`. If no changes were
    # made (nothing was removed) the resulting node is also `self`.
    def without(probe : IProbeDelete) : {Bool, Node(T)}
      self.without(probe, path: probe.path)
    end

    # Branches to mutable or immutable implementation of store.
    protected def with(probe : IProbeAdd(T), path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW
      item = @items.at?(index)

      if item.nil? || (accepted = probe.match?(item)) && (replaced = probe.replace?(item))
        if probe.author? && @writer_items == probe.author?
          @items.with!(index, probe.value)
          return replaced != true, self
        else
          newitems = @items.with(index, probe.value)
          return replaced != true, Node.new(newitems, @children, probe.author?, @writer_children)
        end
      end

      return false, self if accepted

      if child = @children.at?(index)
        created = false
      else
        child = Node(T).new(writer_items: probe.author?, writer_children: probe.author?)
        created = true
      end

      added, newchild = child.with(probe, path >> WINDOW_SIZE)
      return added, self if !created && child.same?(newchild)

      if probe.author? && @writer_children == probe.author?
        @children.with!(index, newchild)
        return added, self
      else
        newchildren = @children.with(index, newchild)
        return added, Node.new(@items, newchildren, @writer_items, probe.author?)
      end
    end

    protected def without(probe : IProbeDelete, path : UInt64) : {Bool, Node(T)}
      index = path & WINDOW
      item = @items.at?(index)

      if item && probe.match?(item)
        if probe.author? && @writer_items == probe.author?
          @items.without!(index)
          return true, self
        else
          newitems = @items.without(index)
          return true, Node.new(newitems, @children, probe.author?, @writer_children)
        end
      end

      return false, self unless child = @children.at?(index)

      removed, newchild = child.without(probe, path >> WINDOW_SIZE)
      return removed, self if child.same?(newchild)

      if newchild.empty?
        if probe.author? && @writer_children == probe.author?
          @children.without!(index)
          return true, self
        else
          newchildren = @children.without(index)
        end
      else
        if probe.author? && @writer_children == probe.author?
          @children.with!(index, newchild)
          return true, self
        else
          newchildren = @children.with(index, newchild)
        end
      end

      {true, Node.new(@items, newchildren, @writer_items, probe.author?)}
    end
  end
end

puts instance_sizeof(Pf::Core::Node(Int32))

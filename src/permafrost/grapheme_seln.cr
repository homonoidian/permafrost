module Pf
  # A string selection type whose indivisible unit is the *grapheme*.
  #
  # See `String::Grapheme` from the standard library for more info on what
  # graphemes are.
  #
  # A string selection is very much like a selection in a text editor. That is,
  # it delimits a chunk of text, within a larger (or equal) body of text. Notably,
  # a selection is never "detached" from the body of text. In terms of lifetimes,
  # in order for a selection to be alive, the text must be alive. This is why
  # selections **must not** be used as a replacement for `String`s. Just because
  # selections are cheap doesn't mean you can use them anywhere. In your mind's
  # eye, you must always picture selections as part of a larger body of text;
  # think "highlighted portions" of text. Whenever you store a selection on the heap,
  # think of it as storing the larger body of text, with a particular region
  # highlighted.
  #
  # Internally, a grapheme selection consists of three things: a *trunk*, the starting
  # grapheme index, and the ending grapheme index (exclusive). That the end index is
  # exclusive means you can have empty selections. Imagine them as "cursors" or "I-beams".
  #
  # A selection *trunk* contains data shared by all selections from the same string.
  # In a way, all selections stem from X, and the most fitting term for X is, arguably,
  # "the trunk".
  #
  # Most importantly, a selection trunk keeps a reference to the original string.
  # We call it the *trunk string*. The reference keeps the trunk string alive.
  # It is also the reason you must not use selections as a generic replacement for strings.
  # If you *really* want to, you should call `detach` where appropriate.
  #
  # There is also the notion of *relative* versus *absolute* indices. A relative index
  # counts from the start of a selection. An absolute index counts from the start of
  # the trunk string instead. Thus we get "absolute byte indices", "relative grapheme
  # indices" and so on.
  #
  # EXPERIMENTAL: Relies on features from the experimental `String::Grapheme` API.
  struct GraphemeSeln
    # :nodoc:
    #
    # Don't waste space on things that don't change for the lifetime of a family
    # of selections.
    #
    # *total* is the number of graphemes in *string*. It is also the size of *offsets*.
    # *offsets* contains one extra element beyond *total*. It holds the bytesize of
    # the string.
    #
    # WARNING: Never EVER access *offsets* directly, it can be NULL as an optimization
    # for ASCII-only strings. Access only through `GraphemeSeln#offsets`.
    class Trunk
      getter total : Int32
      getter string : String
      getter offsets : Int32*

      def initialize(@total, @string, @offsets)
      end

      # Returns the index (absolute) of the grapheme spanning through the given
      # *byte index* (absolute). Raises `IndexError` if *byte index* is out
      # of bounds. Allows *byte_index* to be the bytesize of the trunk string.
      def byte_index_to_grapheme_index(byte_index : Int32) : Int32
        Kit.assert byte_index >= 0

        # For ASCII-only strings, byte index = grapheme index.
        if @offsets.null?
          unless 0 <= byte_index <= @string.bytesize
            raise IndexError.new
          end

          return byte_index
        end

        if byte_index == @string.bytesize
          return @total
        end

        # REMEMBER: offsets is self grapheme size + 1, the extra element at the end
        # is the bytesize. So if e.g. …"A"…, its offsets are, say, [0, 1],
        # we bsearch to get 1's index, then subtract 1, get 0, which is exactly
        # what we want!
        offsets = Slice.new(@offsets, @total + 1, read_only: true)

        index = offsets.bsearch_index { |offset, _| offset > byte_index }
        unless index
          raise IndexError.new
        end

        index - 1
      end
    end

    # Returns the start grapheme index of this selection (absolute).
    getter begin : Int32

    # Returns the end grapheme index of this selection (exclusive; absolute).
    getter end : Int32

    # :nodoc:
    def initialize(@trunk : Trunk, @begin, @end)
      Kit.assert 0 <= @begin <= @end <= @trunk.total
    end

    # Reference: https://github.com/crystal-lang/crystal/blob/066c322f53676e4e59d5e495cc3fa7331c376e8a/src/string/grapheme/grapheme.cr#L10
    private def self.grapheme_bytesize(string : String, byte_start : Int32) : Int32
      state = String::Grapheme::Property::Start
      reader = Char::Reader.new(string, pos: byte_start)
      # cache last_property to avoid re-calculation on the following iteration
      last_property = String::Grapheme::Property.from(reader.current_char)

      while reader.pos < string.bytesize
        char = reader.next_char

        property = String::Grapheme::Property.from(char)
        boundary, state = String::Grapheme.break?(last_property, property, state)
        break if boundary

        last_property = property
      end

      reader.pos - byte_start
    end

    private struct OffsetArray
      getter size : Int32

      def initialize
        @offsets = Pointer(Int32).null
        @capacity = 0
        @size = 0
      end

      def to_unsafe : Int32*
        @offsets
      end

      def present? : Bool
        !@offsets.null?
      end

      def reserve(newsize : Int32) : Nil
        return if newsize <= @capacity

        @capacity = Math.max(@capacity + newsize, @capacity + @capacity//2)
        @offsets = @offsets.realloc(@capacity)
      end

      def <<(offset : Int32) : Nil
        reserve(@size + 1)

        @offsets[@size] = offset
        @size += 1
      end

      # Fills 0 up to *end* (exclusive) with numbers `0`, `1`, `2`, etc.,
      # allocating memory if necessary.
      def iota(end e : Int32) : Nil
        reserve(@size + e)

        e.times do |i|
          @offsets[i] = i
        end

        @size += e
      end

      # Reclaims memory if possible.
      def shrink_to_fit : Nil
        return unless @size < @capacity

        @offsets = @offsets.realloc(@size)
      end
    end

    # Constructs a grapheme selection from *string*.
    def self.new(string : String) : GraphemeSeln
      # TODO: we may want to use a bitmap for @offsets instead of an Int32*. This will save
      # us lots of memory since offsets are predominantly *very* dense. Say, an array of u64s,
      # 16x per bucket, each bucket gets a slot in a "running popcount" u32 array. Since we're
      # build-once-read-only here, we're quite unconstrained here on what we can do. The only
      # real query is select(), which we can answer by bsearching in the popcount array, and
      # then going through the 16xu64 block until we find the u64 that we're searching for.
      # Something like that should work just fine.

      feed = string.to_slice
      offsets = OffsetArray.new

      loop do
        # Since most strings we're dealing with are ASCII, or at least contain
        # significant portions of ASCII, we try process them in a vectorization-
        # friendly way first.
        while feed.size >= 8
          blk = feed.to_unsafe.as(UInt64*).value
          ascii = (blk & 0x80_80_80_80_80_80_80_00u64).zero?
          break unless ascii

          if offsets.present?
            offset = (feed.to_unsafe - string.to_unsafe).to_i
            7.times do
              offsets << offset
              offset += 1
            end
          end

          feed += 7
        end

        break unless byte = feed[0]?

        if byte < 0x80u8 # ASCII
          ahead = feed[1]?
          if ahead.nil? || ahead < 0x80u8 # ... followed by ASCII
            if offsets.present?
              offset = (feed.to_unsafe - string.to_unsafe).to_i
              offsets << offset
            end

            feed += 1
            next
          end
        end

        offset = (feed.to_unsafe - string.to_unsafe).to_i
        if offsets.present?
          offsets << offset
        else
          offsets.iota(offset + 1)
        end

        feed += grapheme_bytesize(string, byte_start: offset)
      end

      unless offsets.present?
        trunk = Trunk.new(total: string.bytesize, string: string, offsets: offsets.to_unsafe)
        return new(trunk, begin: 0, end: string.bytesize)
      end

      offsets << string.bytesize
      offsets.shrink_to_fit

      trunk = Trunk.new(total: offsets.size - 1, string: string, offsets: offsets.to_unsafe)
      new(trunk, begin: 0, end: offsets.size - 1)
    end

    # Returns `true` if selections *a* and *b* originate from the same (or equal-
    # by-value) trunk.
    def self.siblings?(a : GraphemeSeln, b : GraphemeSeln) : Bool
      siblings?(a.@trunk, b.@trunk)
    end

    # :nodoc:
    def self.siblings?(a : Trunk, b : Trunk) : Bool
      a.same?(b) || a.string == b.string
    end

    # Returns the intersection of two selections *a* and *b*. Returns `nil` if
    # they have no intersection.
    def self.intersection?(a : GraphemeSeln, b : GraphemeSeln) : GraphemeSeln?
      Kit.assert siblings?(a, b)

      from = Math.max(a.begin, b.begin)
      to = Math.min(a.end, b.end)
      from <= to ? GraphemeSeln.new(a.@trunk, begin: from, end: to) : nil
    end

    # Returns the number of selected graphemes.
    def size : Int32
      @end - @begin
    end

    # Returns an exclusive range of selected grapheme indices (absolute).
    def range : Range(Int32, Int32)
      @begin...@end
    end

    # Returns the start byte index in the trunk string (absolute).
    def byte_start : Int32
      offsets.unsafe_fetch(0)
    end

    # Returns the end byte index in the trunk string (absolute; exclusive).
    def byte_end : Int32
      offsets.unsafe_fetch(size)
    end

    # Returns the number of selected bytes.
    def bytesize : Int32
      byte_end - byte_start
    end

    # Returns an exclusive range of selected grapheme bytes (absolute).
    def byte_range : Range(Int32, Int32)
      byte_start...byte_end
    end

    # :nodoc:
    struct IdentityOffsets
      include Indexable(Int32)

      def initialize(@begin : Int32, @end : Int32)
      end

      def size : Int
        (@end - @begin) + 1
      end

      def unsafe_fetch(index : Int) : Int32
        @begin + index.to_i
      end
    end

    # Returns JUST THE OFFSETS FOR THIS SELECTION! Not for the trunk!
    private def offsets : Indexable(Int32)
      offsetsptr = @trunk.offsets
      if offsetsptr.null?
        return IdentityOffsets.new(@begin, @end)
      end

      # @trunk.offsets contains one element more than the number of graphemes in
      # @trunk.string, namely, the last element is @trunk.string's bytesize, for
      # ease of use.
      Slice.new(offsetsptr + @begin, size + 1, read_only: true)
    end

    # :nodoc:
    struct IX
      include Indexable(GraphemeView)

      def initialize(@string : String, @offsets : Indexable(Int32))
      end

      def size : Int32
        @offsets.size - 1
      end

      def unsafe_fetch(index : Int) : GraphemeView
        byte_start = @offsets.unsafe_fetch(index)
        byte_end = @offsets.unsafe_fetch(index + 1)

        GraphemeView.new(@string, byte_start, byte_end)
      end
    end

    # Returns an indexable of selected graphemes.
    def ix : Indexable(GraphemeView)
      IX.new(@trunk.string, offsets)
    end

    # Returns `true` if this selection contains zero graphemes.
    def empty? : Bool
      @begin == @end
    end

    # Returns `true` if this selection contains one or more graphemes.
    def present? : Bool
      !empty?
    end

    # Returns `true` if this selection's first grapheme matches *object*.
    #
    # See `GraphemeView#==`.
    def starts_with?(object) : Bool
      return false unless size >= 1

      first.grapheme == object
    end

    # Returns `true` if this selection's last grapheme matches *object*.
    #
    # See `GraphemeView#==`.
    def ends_with?(object) : Bool
      return false unless size >= 1

      last.grapheme == object
    end

    # Returns `true` if this selection comes before *other* in the trunk string.
    def before?(other : GraphemeSeln) : Bool
      GraphemeSeln.siblings?(self, other) && @end <= other.begin
    end

    # Returns `true` if this selection directly precedes *other* in the trunk string.
    # That is, this selection must end where *other* begins for this method to
    # return `true`.
    def contiguous?(other : GraphemeSeln) : Bool
      GraphemeSeln.siblings?(self, other) && @end == other.begin
    end

    # Returns `true` if this selection is fully inside *other*, or if it is
    # the same as *other*.
    def inside?(other lg : GraphemeSeln) : Bool
      GraphemeSeln.siblings?(self, lg) && lg.begin <= @begin <= @end <= lg.end
    end

    # Returns `true` if this selection is fully inside *other*.
    def properly_inside?(other lg : GraphemeSeln) : Bool
      lg.size > size && inside?(lg)
    end

    # Returns `true` if the whole trunk string is selected.
    def covers_fully? : Bool
      size == @trunk.total
    end

    # Asserts that this selection includes exactly one grapheme, and returns
    # a view of that grapheme.
    def grapheme : GraphemeView
      Kit.assert size == 1

      byte_start, byte_end = offsets

      GraphemeView.new(@trunk.string, byte_start, byte_end)
    end

    # Returns a selection containing the first grapheme.
    def first : GraphemeSeln
      Kit.assert @begin < @end

      GraphemeSeln.new(@trunk, begin: @begin, end: @begin + 1)
    end

    # Returns a selection of graphemes after the first one.
    def rest : GraphemeSeln
      Kit.assert @begin < @end

      GraphemeSeln.new(@trunk, begin: @begin + 1, end: @end)
    end

    # Returns a selection of graphemes before the last one.
    def prior : GraphemeSeln
      Kit.assert @begin < @end

      GraphemeSeln.new(@trunk, begin: @begin, end: @end - 1)
    end

    # Returns a selection containing the last grapheme.
    def last : GraphemeSeln
      Kit.assert @begin < @end

      GraphemeSeln.new(@trunk, begin: @end - 1, end: @end)
    end

    # Returns an empty selection before the start of this one.
    def before_start : GraphemeSeln
      GraphemeSeln.new(@trunk, begin: @begin, end: @begin)
    end

    # Returns an empty selection after the end of this one.
    def after_end : GraphemeSeln
      GraphemeSeln.new(@trunk, begin: @end, end: @end)
    end

    # Returns a selection of graphemes before *index* (relative; exclusive).
    def before(index : Int32) : GraphemeSeln
      Kit.assert 0 <= index < size

      GraphemeSeln.new(@trunk, begin: @begin, end: @begin + index)
    end

    # Returns a selection of the grapheme at *index* (relative).
    def at(index : Int32) : GraphemeSeln
      Kit.assert 0 <= index < size

      GraphemeSeln.new(@trunk, begin: @begin + index, end: @begin + index + 1)
    end

    # Returns a selection of graphemes after *index* (relative; exclusive).
    def after(index : Int32) : GraphemeSeln
      Kit.assert 0 <= index < size

      GraphemeSeln.new(@trunk, begin: @begin + index + 1, end: @end)
    end

    # Returns a selection of the grapheme at *byte index* (relative).
    def at_byte(byte_index : Int32) : GraphemeSeln
      at_byte_abs(byte_start + byte_index)
    end

    # Returns a selection of the grapheme at *byte index* (absolute).
    def at_byte_abs(byte_index : Int32) : GraphemeSeln
      abs_grapheme_index = @trunk.byte_index_to_grapheme_index(byte_index)
      Kit.assert @begin <= abs_grapheme_index < @end

      at(abs_grapheme_index - @begin)
    end

    # Shifts this selection by one grapheme to the left (in the trunk string).
    def pred : GraphemeSeln
      return before_start if @begin.zero?

      GraphemeSeln.new(@trunk, begin: @begin - 1, end: @end - 1)
    end

    # Shifts this selection by one grapheme to the right (in the trunk string).
    def succ : GraphemeSeln
      return after_end if @end == @trunk.total

      GraphemeSeln.new(@trunk, begin: @begin + 1, end: @end + 1)
    end

    # Expands this selection to enclose the entirety of the trunk string.
    def expand : GraphemeSeln
      GraphemeSeln.new(@trunk, begin: 0, end: @trunk.total)
    end

    # Returns a copy of this selection which is detached from the trunk.
    #
    # You should imagine this as opening a new buffer in a text editor with
    # the contents of the selection. The old buffer can now be freed by the GC
    # as soon as possible; that's a benefit. The drawback is obviously,
    # the selection loses its context.
    def detach : GraphemeSeln
      if covers_fully?
        return self
      end

      # TODO: This can be optimized. Since we know the offsets we have to
      # copy them & subtract byte_begin from each; that should be faster than
      # iterating over graphemes and all the allocation round-trips we're
      # making here.
      GraphemeSeln.new(to_s)
    end

    # Selects the range of graphemes defined by *from* (relative) and *to*
    # (relative; exclusive).
    def select(from : Int32, to : Int32) : GraphemeSeln
      Kit.assert 0 <= from <= to <= size

      GraphemeSeln.new(@trunk, begin: @begin + from, end: @begin + to)
    end

    # Selects the range of graphemes defined by *range*.
    def select(range : Range(Int32, Int32)) : GraphemeSeln
      self.select(range.begin, range.exclusive? ? range.end : range.end + 1)
    end

    # Selects the range of graphemes defined by *from* (byte index; relative) and
    # *to* (byte index; exclusive; relative).
    def byte_select(from : Int32, to : Int32) : GraphemeSeln
      Kit.assert 0 <= from <= to <= bytesize

      byte_select_abs(byte_start + from, byte_start + to)
    end

    # Selects graphemes in the the range defined by *from* (byte index; absolute) and
    # *to* (byte index; absolute). The *from* grapheme is one that includes the *from*
    # byte index. The *to* grapheme is one that includes the *to* byte index. The *to*
    # grapheme is *excluded* from the resulting selection.
    def byte_select_abs(from : Int32, to : Int32) : GraphemeSeln
      Kit.assert byte_start <= from <= to <= byte_end

      abs_grapheme_from = @trunk.byte_index_to_grapheme_index(from)
      abs_grapheme_to = @trunk.byte_index_to_grapheme_index(to)

      Kit.assert @begin <= abs_grapheme_from <= @end
      Kit.assert @begin <= abs_grapheme_to <= @end

      GraphemeSeln.new(@trunk, begin: abs_grapheme_from, end: abs_grapheme_to)
    end

    # Selects graphemes in the the range defined by *from* (byte index; relative) and
    # *to* (byte index; relative). The *from* grapheme is one that includes the *from*
    # byte index. The *to* grapheme is one that includes the *to* byte index. The *to*
    # grapheme is *included* in the resulting selection.
    def byte_select_inclusive(from : Int32, to : Int32) : GraphemeSeln
      Kit.assert 0 <= from <= to < bytesize

      byte_select_abs_inclusive(byte_start + from, byte_start + to)
    end

    # Selects graphemes in the the range defined by *from* (byte index; absolute) and
    # *to* (byte index; absolute). The *from* grapheme is one that includes the *from*
    # byte index. The *to* grapheme is one that includes the *to* byte index. The *to*
    # grapheme is *included* in the resulting selection.
    def byte_select_abs_inclusive(from : Int32, to : Int32) : GraphemeSeln
      Kit.assert byte_start <= from <= to <= byte_end

      abs_grapheme_from = @trunk.byte_index_to_grapheme_index(from)
      abs_grapheme_to = @trunk.byte_index_to_grapheme_index(to)

      Kit.assert @begin <= abs_grapheme_from < @end
      Kit.assert @begin <= abs_grapheme_to < @end

      GraphemeSeln.new(@trunk, begin: abs_grapheme_from, end: abs_grapheme_to + 1)
    end

    # Selects all graphemes between this selection's start and *other*'s end.
    def through(other : GraphemeSeln) : GraphemeSeln
      Kit.assert @begin <= @end <= other.begin

      GraphemeSeln.new(@trunk, begin: @begin, end: other.begin)
    end

    # Splits this selection into three: one before the leftmost grapheme matching
    # *object*, one with just that grapheme, and one after the grapheme. If there
    # is no grapheme matching *object*, the first selection is `self`, and the last
    # two point `after_end`.
    #
    # NOTE: Comparison of each grapheme with *object* is performed using `GraphemeView#==`.
    def partition(object) : {GraphemeSeln, GraphemeSeln, GraphemeSeln}
      partition { |grapheme| grapheme == object }
    end

    # Splits this selection into three: one before the leftmost grapheme for which
    # the block returns `true`, one with just that grapheme, and one after the grapheme.
    # If there is no grapheme matching *object*, the first selection is `self`,
    # and the last two point `after_end`.
    def partition(& : GraphemeView -> Bool) : {GraphemeSeln, GraphemeSeln, GraphemeSeln}
      ix.each_with_index do |grapheme, index|
        next unless yield grapheme
        return before(index), at(index), after(index)
      end

      {self, after_end, after_end}
    end

    # Joins two selections into one. An important requirement is that `self` and
    # *other* must form a contiguous sequence (see `contiguous?`).
    def +(other : GraphemeSeln) : GraphemeSeln
      Kit.assert contiguous?(other)

      GraphemeSeln.new(@trunk, begin: @begin, end: other.end)
    end

    # Splits this selection at newlines (`\n`) and yields each resulting fragment.
    # Note that newlines themselves are *not* removed, so fragments may or may not
    # end with a newline. An important property of this method is that the yielded
    # fragments form a contiguous sequence (so you can e.g. join `+` them back to get
    # this (original) selection).
    def each_line(& : GraphemeSeln ->) : Nil
      split('\n') { |line| yield line }
    end

    # Splits this selection at *object*s and yields each resulting fragment.
    # The yielded fragments form a contiguous sequence.
    #
    # NOTE: Comparison of each grapheme with *object* is performed using `GraphemeView#==`.
    def split(object, & : GraphemeSeln ->) : Nil
      remainder = self

      loop do
        before, at, after = remainder.partition(object)
        break if at.empty?

        yield before + at

        remainder = after
      end

      yield remainder
    end

    # Splits based on an external "mask" or annotation array, aligned with the *trunk
    # string*'s bytes. Yields the part before a delimiter (first block arg) separately
    # from the delimiter itself (the second block arg). The delimiter is empty at the end.
    def byte_mask_split(objects : Indexable(T), object : T, & : GraphemeSeln, GraphemeSeln ->) : Nil forall T
      remainder = self

      loop do
        before, at, after = remainder.partition do |grapheme|
          objects[grapheme.byte_start] == object
        end

        break if at.empty?

        yield before, at

        remainder = after
      end

      yield remainder, remainder.after_end
    end

    # Shrinks this selection so that it does not end with trailing LF `\n`
    # or CRLF `\r\n`.
    def chomp : GraphemeSeln
      if ends_with?('\r')
        prior
      elsif ends_with?('\n')
        prefix = prior
        if prefix.ends_with?('\r') # \r\n
          return prefix.prior
        end

        prefix
      else
        self
      end
    end

    # Yields selections of contiguous runs of graphemes for which the given *segmenter*
    # function produced the same value, along with that value.
    def each_segment(segmenter : GraphemeView -> T, & : T, GraphemeSeln ->) forall T
      state = Tuple.new
      start = 0

      ix.each_with_index do |grapheme, index|
        successor = {segmenter.call(grapheme)}
        next if state == successor

        case state
        in Tuple()
        in Tuple(T)
          yield state[0], GraphemeSeln.new(@trunk, begin: @begin + start, end: @begin + index)
        end

        state = successor
        start = index
      end

      case state
      in Tuple()
      in Tuple(T)
        yield state[0], GraphemeSeln.new(@trunk, begin: @begin + start, end: @begin + size)
      end
    end

    # Returns a read-only view of the underling bytes of this selection. The view
    # is a subview of the trunk string's bytes.
    def to_slice : Bytes
      Slice.new(@trunk.string.to_unsafe + byte_start, bytesize, read_only: true)
    end

    def inspect(io)
      io << "…\""
      ix.each do |grapheme|
        grapheme.to_s.dump_unquoted(io)
      end
      io << "\"…"
    end

    def to_s(io)
      io.write(to_slice)
    end

    def to_s
      if covers_fully?
        return @trunk.string
      end

      super
    end

    # Returns `true` if the content of this selection is equal, bytewise, to that
    # of *other*.
    def ==(other : String) : Bool
      to_slice == other.to_slice
    end

    # Two grapheme selections are equal if their strings are equal, and the selections
    # "highlight" the same part of the string.
    def ==(other : GraphemeSeln) : Bool
      return false unless GraphemeSeln.siblings?(self, other)
      return false unless @begin == other.begin
      return false unless @end == other.end

      true
    end
  end
end

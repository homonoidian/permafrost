struct Pf::StringSeln
  # :nodoc:
  #
  # WARNING: *bytes* MUST be valid UTF-8 bytes.
  # WARNING: *bytes* MUST start and end on UTF-8 character boundaries.
  # WARNING: *bytesize* must be in `1..4`.
  def self.unsafe_chr(bytes : UInt8*, bytesize : UInt32) : Char
    case bytesize
    when 1u32
      codepoint = bytes[0]
    when 2u32
      byte0 = bytes[0].to_u32
      byte1 = bytes[1].to_u32
      codepoint = ((byte0 & 0x1F) << 6) | (byte1 & 0x3F)
    when 3u32
      byte0 = bytes[0].to_u32
      byte1 = bytes[1].to_u32
      byte2 = bytes[2].to_u32
      codepoint = ((byte0 & 0x0F) << 12) | ((byte1 & 0x3F) << 6) | (byte2 & 0x3F)
    when 4u32
      byte0 = bytes[0].to_u32
      byte1 = bytes[1].to_u32
      byte2 = bytes[2].to_u32
      byte3 = bytes[3].to_u32
      codepoint = ((byte0 & 0x07) << 18) | ((byte1 & 0x3F) << 12) | ((byte2 & 0x3F) << 6) | (byte3 & 0x3F)
    else
      Intrinsics.unreachable
    end

    codepoint.unsafe_chr
  end

  # :nodoc:
  #
  # WARNING: *bytes* MUST be valid UTF-8 bytes.
  # WARNING: *bytes* MUST start and end on UTF-8 character boundaries.
  def self.unsafe_chrsize_and_flags(bytes : UInt8*, bytesize : UInt32) : {UInt32, SelnFlags}
    if bytesize.zero?
      return 0u32, SelnFlags::None
    end

    head = bytes[0]
    if head >= 0x80
      return (~head).leading_zeros_count.to_u32, SelnFlags::None
    end

    {1u32, SelnFlags::AsciiChar}
  end

  # :nodoc:
  #
  # WARNING: *bytes* MUST be valid UTF-8 bytes.
  # WARNING: *bytes* MUST start and end on UTF-8 character boundaries.
  def self.unsafe_rchrsize_and_flags(bytes : UInt8*, bytesize : UInt32) : {UInt32, SelnFlags}
    if bytesize.zero?
      return 0u32, SelnFlags::None
    end

    # We're unsafe, and *bytes* is valid UTF-8, so we consider OOB impossible here;
    # i.e., if valid UTF-8 says "continue", we continue.

    unless (bytes[bytesize &- 1] & 0xC0) == 0x80
      return 1u32, SelnFlags::AsciiChar
    end

    unless (bytes[bytesize &- 2] & 0xC0) == 0x80
      return 2u32, SelnFlags::None
    end

    unless (bytes[bytesize &- 3] & 0xC0) == 0x80
      return 3u32, SelnFlags::None
    end

    {4u32, SelnFlags::None}
  end

  private def self.continuation_byte?(byte : UInt8) : Bool
    {byte.bit(7), byte.bit(6)} == {1, 0}
  end

  private def self.continuation_count(bytes : Bytes) : Int32
    if bytes.size == 8
      blks = bytes.unsafe_slice_of(UInt64)
      blk = blks.unsafe_fetch(0)
      mask = (blk & 0x8080808080808080u64) & ~(blk << 1)
      return mask.popcount.to_i
    end

    count = 0

    bytes.each do |byte|
      next unless continuation_byte?(byte)

      # See the NOTE below: continuation count can never exceed bytesize, and
      # bytesize is in Int32.
      count &+= 1
    end

    count
  end

  # :nodoc:
  #
  # WARNING: *bytes* MUST be valid UTF-8 bytes.
  # WARNING: *bytes* MUST start and end on UTF-8 character boundaries.
  def self.unsafe_measure(bytes : Bytes) : Int32
    # NOTE: Max continuation count is *bytes* bytesize which is in Int32 bounds.
    continuation_count = 0
    bytes.in_chunks_of(size_lte: 8) do |blk|
      continuation_count &+= continuation_count(blk)
    end

    size = bytes.size - continuation_count
    assert size >= 0

    size
  end

  def self.unsafe_gte?(bytes : Bytes, size : Int32) : Bool
    # NOTE: Max continuation count is *bytes* bytesize which is in Int32 bounds.
    continuation_count = 0
    bytes.in_chunks_of(size_lte: 8) do |blk|
      continuation_count &+= continuation_count(blk)
      if continuation_count >= size
        return true
      end
    end

    false
  end
end

# A string selection type whose indivisible unit is the *character* (`Char`).
#
# See also: `GraphemeSeln`.
#
# `StringSeln` is most useful for lexical analysis/parsing and similar. Do not
# use it as a general-purpose replacement for strings: string selections do not
# play well with the GC since they keep the whole string in memory even if all
# you have at that point is its tiny (or even empty) fragment.
struct Pf::StringSeln
  # Returns the starting byte of this selection (inclusive).
  getter byte_start : UInt32
  # Returns the ending byte of this selection (exclusive).
  getter byte_end : UInt32

  @[Flags]
  enum SelnFlags : UInt32
    AsciiChar
  end

  # :nodoc:
  #
  # WARNING: *trunk* MUST be valid UTF-8.
  # WARNING: `byte_start <= byte_end <= trunk.bytesize` must be true.
  def initialize(@trunk : String, @byte_start : UInt32, @byte_end : UInt32, @flags : SelnFlags = SelnFlags::None)
    # We call this a lot, sometimes per character, so checking this every time
    # is quite expensive.
    {% if flag?(:safe) %}
      assert @byte_start <= @byte_end <= @trunk.bytesize
    {% end %}
  end

  # Constructs a string selection from the given *string*.
  #
  # This forces an encoding check on *string*. This method requires *string* to
  # be a valid UTF-8 string.
  #
  # If you want to `scrub`, use `new_scrub` instead to skip the check.
  def self.new(string : String) : StringSeln
    new?(string) || raise ArgumentError.new("string must be valid UTF-8")
  end

  def self.new?(string : String) : StringSeln?
    return unless string.valid_encoding?

    new(string, byte_start: 0u32, byte_end: string.bytesize.to_u32)
  end

  # Constructs a string selection from the given *string*, replacing invalid
  # bytes (according to UTF-8) with *replacement*.
  #
  # See also: `String#scrub`.
  #
  # Prefer this method over `new(string.scrub)` to avoid the overhead of validating
  # the encoding.
  def self.new_scrub(string : String, replacement : Char = Char::REPLACEMENT) : StringSeln
    string = string.scrub(replacement)

    new(string, byte_start: 0u32, byte_end: string.bytesize.to_u32)
  end

  # Returns `true` if *seln*, *selns* are all of common descent, pointing
  # to the same trunk.
  def self.siblings?(seln ref : StringSeln, *selns : StringSeln) : Bool
    selns.all? { |seln| ref.@trunk.same?(seln.@trunk) }
  end

  def self.contiguous?(a : StringSeln, b : StringSeln) : Bool
    siblings?(a, b) && a.byte_end <= b.byte_start
  end

  # Joins two contiguous selections *a*, *b*. *a* must end exactly where *b* begins.
  def self.chain(a : StringSeln, b : StringSeln) : StringSeln
    assert siblings?(a, b)
    assert a.byte_end == b.byte_start

    new(a.@trunk, a.byte_start, b.byte_end)
  end

  def self.span(a : StringSeln, b : StringSeln) : StringSeln
    assert siblings?(a, b)

    new(a.@trunk, a.byte_start, b.byte_end)
  end

  def self.between(a : StringSeln, b : StringSeln) : StringSeln
    assert contiguous?(a, b)

    new(a.@trunk, a.byte_end, b.byte_start)
  end

  def self.extend(a : StringSeln, b : StringSeln) : StringSeln
    assert siblings?(a, b)

    new(a.@trunk, a.byte_start, b.byte_start)
  end

  private def startptr : UInt8*
    @trunk.to_unsafe + @byte_start
  end

  def <=>(other : StringSeln) : Int32
    # Fast path.
    if @trunk.same?(other.@trunk) && {byte_start, byte_end} == {other.byte_start, other.byte_end}
      return 0
    end

    (to_slice <=> other.to_slice).sign
  end

  # Returns the number of selected bytes.
  def bytesize : UInt32
    @byte_end &- @byte_start
  end

  def byte_range : Range(UInt32, UInt32)
    @byte_start...@byte_end
  end

  # Expands this selection to enclose the entire trunk string.
  def expand : StringSeln
    StringSeln.new(@trunk, 0u32, @trunk.bytesize)
  end

  # Returns the index of the first selected character.
  def char_start : UInt32
    offset = 0u64
    index = 0u32

    loop do
      chrsize, _ = StringSeln.unsafe_chrsize_and_flags(@trunk.to_unsafe + offset, @trunk.bytesize.to_u32)
      if offset == @byte_start
        return index
      end

      offset += chrsize
      index += 1
    end
  end

  # Returns the index of the last selected character.
  def char_end : UInt32
    offset = 0u64
    index = 0u32

    loop do
      chrsize, _ = StringSeln.unsafe_chrsize_and_flags(@trunk.to_unsafe + offset, @trunk.bytesize.to_u32)
      if offset == @byte_end
        return index
      end

      offset += chrsize
      index += 1
    end
  end

  # Returns the number of selected characters.
  #
  # NOTE: Unlike `String`, this method does *not* cache the size -- since
  # `StringSeln` is located entirely on the stack (minus the trunk string),
  # there's nowhere for the size to go.
  #
  # However, I tried to optimize this method well. In fact, due to the invariants
  # of `StringSeln`, it runs about 10x faster than uncached `String#size` on
  # my machine (the example I used was a 20MiB string; the results were: Crystal ~11ms,
  # StringSeln ~1.25ms).
  #
  # The design is that you aren't expected to call this method very often. If you
  # do end up doing that, we try really hard to remain fast, but ultimately,
  # this is still worst-case O(N).
  def size : Int32
    StringSeln.unsafe_measure(to_slice)
  end

  # Returns `true` if this selection contains zero characters.
  def empty? : Bool
    @byte_start == @byte_end
  end

  # Returns `true` if this selection contains one or more characters.
  def nonempty? : Bool
    !empty?
  end

  def covers_fully? : Bool
    {@byte_start, @byte_end} == {0u32, @trunk.bytesize.to_u32}
  end

  def includes?(object : Char) : Bool
    each_char do |chr|
      return true if chr == object
    end

    false
  end

  def prefixed_by?(l : Char | String) : Bool
    bytesize > l.bytesize && starts_with?(l)
  end

  def postfixed_by?(r : Char | String) : Bool
    bytesize > r.bytesize && ends_with?(r)
  end

  def surrounded_by?(l : Char | String, r : Char | String) : Bool
    bytesize > l.bytesize + r.bytesize && starts_with?(l) && ends_with?(r)
  end

  def starts_with?(prefix : Char) : Bool
    bytesize >= prefix.bytesize && first_char == prefix
  end

  def starts_with?(prefix : String) : Bool
    to_slice.starts_with?(prefix.to_slice)
  end

  def ends_with?(suffix : Char) : Bool
    bytesize >= suffix.bytesize && suffix == last_char
  end

  def ends_with?(suffix : String) : Bool
    to_slice.ends_with?(suffix.to_slice)
  end

  # Returns `true` if this selection is empty or contains exclusively
  # whitespace (see `Char#whitespace?`).
  def blank? : Bool
    each_char do |chr|
      next if chr.whitespace?
      return false
    end

    true
  end

  # Splits this selection into two: the first selection contains the first
  # character, and the second one contains the rest of characters. If this
  # selection is empty, returns two empty selections.
  def first_and_rest : {StringSeln, StringSeln}
    chrsize, flags = StringSeln.unsafe_chrsize_and_flags(startptr, bytesize)
    first = StringSeln.new(@trunk, @byte_start, @byte_start + chrsize, flags)
    rest = StringSeln.new(@trunk, @byte_start + chrsize, @byte_end)
    {first, rest}
  end

  # Splits this selection into two: the first selection contains characters before
  # the last character, and the second selection contains the last character.
  def prior_and_last : {StringSeln, StringSeln}
    chrsize, flags = StringSeln.unsafe_rchrsize_and_flags(startptr, bytesize)
    prior = StringSeln.new(@trunk, @byte_start, @byte_end - chrsize, flags)
    last = StringSeln.new(@trunk, @byte_end - chrsize, @byte_end)
    {prior, last}
  end

  # Selects the *first* character if there are one or more characters. If there are
  # zero characters, the returned selection is empty.
  def first : StringSeln
    first, _ = first_and_rest
    first
  end

  # Selects characters after the *first* character in this selection. If there are
  # zero characters, the returned selection is empty.
  def rest : StringSeln
    _, rest = first_and_rest
    rest
  end

  # Selects characters before the *last* character in this selection. If there are
  # zero characters, the returned selection is empty.
  def prior : StringSeln
    prior, _ = prior_and_last
    prior
  end

  # Selects the *last* character if there is one or more characters. If there are
  # zero characters, the returned selection is empty.
  def last : StringSeln
    _, last = prior_and_last
    last
  end

  # Returns an empty selection pointing before the beginning of this one. Imagine
  # this as placing an "I-beam" before the first character in this selection (if any).
  def before_begin : StringSeln
    StringSeln.new(@trunk, @byte_start, @byte_start)
  end

  # Selects all characters in the trunk string before the start of this selection.
  def all_before_begin : StringSeln
    StringSeln.new(@trunk, 0u32, @byte_start)
  end

  # Returns an empty selection pointing after the end of this one. Imagine this
  # this as placing an "I-beam" after the last character in this selection (if any).
  def after_end : StringSeln
    StringSeln.new(@trunk, @byte_end, @byte_end)
  end

  # Selects all characters in the trunk string after the end of this selection.
  def all_after_end : StringSeln
    StringSeln.new(@trunk, @byte_end, @trunk.bytesize.to_u32)
  end

  # :nodoc:
  def chr : Char
    if @flags.ascii_char? # Fast path
      return startptr[0].unsafe_chr
    end

    assert 1u32 <= bytesize <= 4u32

    StringSeln.unsafe_chr(startptr, bytesize)
  end

  # Returns the first character in this selection. Raises `IndexError` if
  # this selection is empty.
  def first_char : Char
    first_char? || raise IndexError.new
  end

  # Returns the last character in this selection. Raises `IndexError` if
  # this selection is empty.
  def last_char : Char
    last_char? || raise IndexError.new
  end

  # Returns the first character in this selection. Returns `nil` if
  # this selection is empty.
  def first_char? : Char?
    empty? ? nil : first.chr
  end

  # Returns the last character in this selection. Returns `nil` if
  # this selection is empty.
  def last_char? : Char?
    empty? ? nil : last.chr
  end

  def each_char_seln(& : StringSeln ->) : Nil
    remainder = self

    until remainder.empty?
      first, rest = remainder.first_and_rest
      yield first

      remainder = rest
    end
  end

  def reverse_each_char_seln(& : StringSeln ->) : Nil
    remainder = self

    until remainder.empty?
      prior, last = remainder.prior_and_last
      yield last

      remainder = prior
    end
  end

  struct EE
    include Enumerable(Char)

    def initialize(@seln : StringSeln)
    end

    def each(& : Char ->)
      @seln.each_char { |chr| yield chr }
    end
  end

  def ee : Enumerable(Char)
    EE.new(self)
  end

  # Yields selected characters.
  def each_char(& : Char ->) : Nil
    each_char_seln { |seln| yield seln.chr }
  end

  # Yields selected characters along with their *absolute* byte index.
  def each_char_with_abs_byte_index(& : Char, Int32 ->) : Nil
    each_char_seln do |seln|
      yield seln.chr, seln.byte_start.to_i # ?!
    end
  end

  # Yields selected characters in reverse.
  def reverse_each_char(& : Char ->) : Nil
    reverse_each_char_seln { |seln| yield seln.chr }
  end

  def each_char_with_index(& : Char, Int32 ->) : Nil
    index = 0

    each_char_seln do |seln|
      yield seln.chr, index

      index += 1
    end
  end

  def each_before_and_after(& : StringSeln, StringSeln ->) : Nil
    each_char_seln do |seln|
      before = StringSeln.between(before_begin, seln.before_begin)
      after = StringSeln.between(seln.before_begin, after_end)
      yield before, after
    end

    yield self, after_end
  end

  def reverse_each_before_and_after(& : StringSeln, StringSeln ->) : Nil
    yield self, after_end

    reverse_each_char_seln do |seln|
      before = StringSeln.between(before_begin, seln.before_begin)
      after = StringSeln.between(seln.before_begin, after_end)
      yield before, after
    end
  end

  def each_partition(& : StringSeln, StringSeln, StringSeln ->) : Nil
    each_char_seln do |seln|
      l = StringSeln.between(before_begin, seln.before_begin)
      m = seln
      r = StringSeln.between(seln.after_end, after_end)
      yield l, m, r
    end

    yield self, after_end, after_end
  end

  def reverse_each_partition(& : StringSeln, StringSeln, StringSeln ->) : Nil
    yield self, after_end, after_end

    reverse_each_char_seln do |seln|
      l = StringSeln.between(before_begin, seln.before_begin)
      m = seln
      r = StringSeln.between(seln.after_end, after_end)
      yield l, m, r
    end
  end

  def each_split(& : StringSeln, StringSeln, StringSeln ->) : Nil
    each_partition do |l, m, r|
      return if m.empty? # last
      yield l, m, r
    end
  end

  def reverse_each_split(& : StringSeln, StringSeln, StringSeln ->) : Nil
    reverse_each_partition do |l, m, r|
      next if m.empty? # last
      yield l, m, r
    end
  end

  # Yields each word in this selection.
  #
  # This method never consumes any characters. All trailing and leading whitespaces
  # are kept (if any) -- attached either to the left- or the right-hand side word.
  def each_word(& : StringSeln ->) : Nil
    l, sep0, r = partition(' ')

    loop do
      yield l unless l.empty?

      break if sep0.empty?

      if r.empty?
        yield sep0
        break
      end

      succ, sep1, r1 = r.partition(' ')

      l = sep0 &+ succ
      sep0 = sep1
      r = r1
    end
  end

  # Yields each word in this selection along with its index.
  #
  # See also: `each_word`.
  def each_word_with_index(& : StringSeln, Int32 ->) : Nil
    index = 0

    each_word do |word|
      yield word, index

      index += 1
    end
  end

  def each_line(& : StringSeln ->)
    remainder = self

    until remainder.empty?
      l, m, remainder = remainder.partition('\n')
      yield l &+ m
    end
  end

  def each_line_with_index(& : StringSeln, Int32 ->)
    index = 0

    each_line do |line|
      yield line, index

      index += 1
    end
  end

  def partition(& : Char -> Bool) : {StringSeln, StringSeln, StringSeln}
    each_split do |l, m, r|
      chr = m.chr
      if yield chr
        return l, m, r
      end
    end

    {self, after_end, after_end}
  end

  def partition(pattern : Char) : {StringSeln, StringSeln, StringSeln}
    partition { |chr| chr === pattern }
  end

  def partition(index needle : Int) : {StringSeln, StringSeln, StringSeln}
    index = 0

    each_split do |l, m, r|
      if index == needle
        return l, m, r
      end

      index += m.bytesize
    end

    {self, after_end, after_end}
  end

  def rpartition(& : Char -> Bool) : {StringSeln, StringSeln, StringSeln}
    reverse_each_split do |l, m, r|
      chr = m.chr
      if yield chr
        return l, m, r
      end
    end

    {before_begin, before_begin, self}
  end

  def rpartition(pattern : Char) : {StringSeln, StringSeln, StringSeln}
    rpartition { |chr| chr === pattern }
  end

  def split(sep : Char, **kwargs) : Array(StringSeln)
    segments = [] of StringSeln

    split(sep, **kwargs) do |segment|
      segments << segment
    end

    segments
  end

  def split(sep : Char, **kwargs, &) : Nil
    split_and_rest(sep, **kwargs) do |segment, _|
      yield segment
    end
  end

  def split_and_rest(sep : Char, *, allow_empty : Bool = true, & : StringSeln, StringSeln ->) : Nil
    remainder = self

    loop do
      l, m, remainder = remainder.partition(sep)
      if l.nonempty? || allow_empty
        yield l, remainder
      end

      break if m.empty?
    end
  end

  def &+(other : StringSeln) : StringSeln
    StringSeln.chain(self, other)
  end

  # Returns a selection that excludes the first selected character.
  def lchop : StringSeln
    _, rest = first_and_rest
    rest
  end

  # Returns a selection that excludes the last selected character.
  def rchop : StringSeln
    prior, _ = prior_and_last
    prior
  end

  # Skips one leading character *chr* from this selection, if present.
  def lchop(chr : Char) : StringSeln
    lchop?(chr) || self
  end

  # Skips one trailing character *chr* from this selection, if present.
  def rchop(chr : Char) : StringSeln
    rchop?(chr) || self
  end

  # Skips one leading character *chr* from this selection, if present.
  # Returns `nil` if *chr* is absent.
  def lchop?(pattern : Char) : StringSeln?
    return if empty?

    first, rest = first_and_rest
    first.chr == pattern ? rest : nil
  end

  def lchop?(pattern : String) : StringSeln?
    return unless starts_with?(pattern)

    StringSeln.new(@trunk, @byte_start + pattern.bytesize, @byte_end)
  end

  def rchop?(chr : Char) : StringSeln?
    return if empty?

    prior, last = prior_and_last
    last.chr == chr ? prior : nil
  end

  def rchop?(pattern : String) : StringSeln?
    return unless ends_with?(pattern)

    StringSeln.new(@trunk, @byte_start, @byte_end - pattern.bytesize)
  end

  def chop?(l, r) : StringSeln?
    remainder = self
    return unless remainder = remainder.lchop?(l)
    return unless remainder = remainder.rchop?(r)

    remainder
  end

  def chomp : StringSeln
    if ends_with?('\r')
      return prior
    end

    if ends_with?('\n')
      prefix = prior
      if prefix.ends_with?('\r') # \r\n
        return prefix.prior
      end

      return prefix
    end

    self
  end

  def strip(charset : String = "\n") : StringSeln
    lstrip(charset).rstrip(charset)
  end

  def lstrip(charset : String = "\n") : StringSeln
    _, r = skip_thru(charset)
    r
  end

  def rstrip(charset : String = "\n") : StringSeln
    l, _ = rskip_thru(charset)
    l
  end

  def skip_thru_seq(*, limit : UInt32 = UInt32::MAX, & : Char -> T?) : {StringSeln, Array(T), StringSeln} forall T
    seq = [] of T
    remainder = self

    until remainder.empty? || limit.zero?
      first, rest = remainder.first_and_rest

      object = yield first.chr
      break if object.nil?

      seq << object
      remainder = rest
      limit -= 1
    end

    {StringSeln.between(before_begin, remainder), seq, remainder}
  end

  def skip_thru(charset : String) : {StringSeln, StringSeln}
    l, m, r = partition { |chr| !chr.in_set?(charset) }
    {l, m &+ r}
  end

  def rskip_thru(charset : String) : {StringSeln, StringSeln}
    l, m, r = rpartition { |chr| !chr.in_set?(charset) }
    {l &+ m, r}
  end

  def skip_to(charset : String) : {StringSeln, StringSeln}
    l, m, r = partition(&.in_set?(charset))
    {l, m &+ r}
  end

  def rskip_to(charset : String) : {StringSeln, StringSeln}
    l, m, r = rpartition(&.in_set?(charset))
    {l &+ m, r}
  end

  # Skips a number of characters from the left.
  def lskip(nchars : Int) : StringSeln
    remainder = self

    nchars.times do
      break if remainder.empty?

      remainder = remainder.rest
    end

    remainder
  end

  def ltake?(pattern) : StringSeln?
    return unless starts_with?(pattern)

    StringSeln.new(@trunk, @byte_start, @byte_start + pattern.bytesize)
  end

  def find(pattern) : StringSeln
    each_before_and_after do |before, after|
      if segment = after.ltake?(pattern)
        return segment
      end
    end

    raise ArgumentError.new("not found")
  end

  def extend(*, exclusive = true, & : Char -> Bool) : StringSeln
    l, m, _ = all_after_end.partition { |chr| !(yield chr) }
    unless exclusive
      l &+= m
    end

    StringSeln.between(before_begin, l.after_end)
  end

  def reverse_extend(*, exclusive = true, & : Char -> Bool) : StringSeln
    _, m, r = all_before_begin.rpartition { |chr| !(yield chr) }
    unless exclusive
      r = m &+ r
    end

    StringSeln.between(r.before_begin, after_end)
  end

  def span(other : StringSeln) : StringSeln
    StringSeln.span(self, other)
  end

  def upto(other : StringSeln) : StringSeln
    StringSeln.extend(self, other)
  end

  # A hand-optimized alternative to `ee.count`. This is about a hundred times faster
  # than `ee.count` on my machine for basic tasks such as counting newlines, due to
  # vectorization-friendliness in the single-byte fast path.
  def count(pattern : Char) : Int32
    buffer = uninitialized UInt8[4]
    buffer_size = 0

    pattern.each_byte do |byte|
      buffer[buffer_size] = byte
      buffer_size += 1
    end

    ptr = startptr
    ptrsize = bytesize
    count = 0u32

    # Fast path for single-byte chars. This can be auto-vectorized with --mcpu=native.
    if buffer_size == 1
      needle = buffer.unsafe_fetch(0)

      ptrsize.times do |index|
        if ptr[index] == needle
          # Worst case is count = bytesize. Bytesize is proven to be UInt32.
          # So an overflow is impossible.
          count &+= 1
        end
      end

      return count.to_i # ?!
    end

    until ptrsize.zero?
      match = (0...buffer_size).all? do |index|
        ptr[index] == buffer.unsafe_fetch(index)
      end

      if match
        # Worst case is count = bytesize. Bytesize is proven to be UInt32.
        # So an overflow is impossible.
        count &+= 1
      end

      ptr += 1
      ptrsize &-= 1
    end

    count.to_i # ?!
  end

  # Returns the underlying bytes. The returned slice is read-only.
  # It is guaranteed to contain valid UTF-8 encoded bytes. It is
  # guaranteed to start and end at a UTF-8 character boundary.
  def to_slice : Bytes
    Bytes.new(startptr, bytesize, read_only: true)
  end

  def clone : StringSeln
    self
  end

  def highlight(io, marker : String = "⏏")
    b = char_start

    if bytesize.zero?
      io << @trunk.insert(b, marker)
      return
    end

    e = char_end

    io << @trunk.insert(e, marker).insert(b, marker)
  end

  def inspect(io)
    io << "…\""

    each_char do |chr|
      case chr
      when '"'  then io << "\\\""
      when '\\' then io << "\\\\"
      when '\a' then io << "\\a"
      when '\b' then io << "\\b"
      when '\e' then io << "\\e"
      when '\f' then io << "\\f"
      when '\n' then io << "\\n"
      when '\r' then io << "\\r"
      when '\t' then io << "\\t"
      when '\v' then io << "\\v"
      when '\0' then io << "\\0"
      else
        if chr.printable?
          io << chr
        else
          chr.unicode_escape(io)
        end
      end
    end

    io << "\"…"
  end

  def to_s(io)
    io.write(to_slice)
  end

  def to_s : String
    if covers_fully?
      return @trunk
    end

    @trunk.byte_slice(@byte_start, bytesize)
  end

  def ==(other : StringSeln) : Bool
    # Fast path.
    if @trunk.same?(other.@trunk) && {byte_start, byte_end} == {other.byte_start, other.byte_end}
      return true
    end

    to_slice == other.to_slice
  end

  def ==(other : String) : Bool
    to_slice == other.to_slice
  end

  def ==(other : Char) : Bool
    bytesize == other.bytesize && starts_with?(other)
  end

  def_hash to_slice
end

module Pf
  # Represents a single grapheme as a view into a string.
  #
  # NOTE: `GraphemeView`, just like `GraphemeSeln`, refers back to the trunk
  # string, which could be very large. This may prevent the GC from freeing large
  # chunks of memory due to a small number of grapheme views that refer to it. For
  # this reason, you are advised not to store `GraphemeView`s on the heap unless
  # you know for sure their lifetime is less than or equal to the lifetime of the trunk
  # string. Otherwise, use `to_grapheme`. In general, when working with `GraphemeView`,
  # the reasoning should be the same as with `GraphemeSeln`; in that they carry around,
  # at least conceptually, the larger context as well.
  #
  # EXPERIMENTAL: Relies on features from the experimental `String::Grapheme` API.
  struct GraphemeView
    # Returns the byte index of this grapheme in the trunk string.
    getter byte_start : Int32

    # Returns the byte index of this grapheme in the trunk string.
    getter byte_end : Int32

    # :nodoc:
    def initialize(@string : String, @byte_start, @byte_end)
      Kit.assert 0 <= @byte_start < @byte_end <= @string.bytesize
    end

    # Returns the size of this grapheme in bytes.
    def bytesize : Int32
      @byte_end - @byte_start
    end

    # Returns an exclusive range of the indices of the contituent bytes of
    # this grapheme in the trunk string.
    def byte_range : Range(Int32, Int32)
      @byte_start...@byte_end
    end

    # Returns a read-only view of the underling bytes of this grapheme. The view
    # is a subview of the trunk string's bytes.
    def to_slice : Bytes
      Slice.new(@string.to_unsafe + @byte_start, bytesize, read_only: true)
    end

    # Converts this view to a `String::Grapheme`.
    def to_grapheme : String::Grapheme
      reader = Char::Reader.new(@string, pos: @byte_start)

      String::Grapheme.new(@string, byte_range, reader.current_char)
    end

    def to_s(io)
      io.write((@string.to_unsafe + @byte_start).to_slice(@byte_end - @byte_start))
    end

    def inspect(io)
      io << "…'" << @string.byte_slice(@byte_start, @byte_end - @byte_start) << "'…"
    end

    # Returns `true` if this view consists only of the character *other*.
    def ==(other : Char) : Bool
      return false unless bytesize == other.bytesize

      buffer = uninitialized UInt8[4]
      buffer_size = 0

      other.each_byte do |byte|
        buffer[buffer_size] = byte
        buffer_size += 1
      end

      to_slice == Slice.new(buffer.to_unsafe, buffer_size, read_only: true)
    end

    # Compares the contents of this view with *other*, bytewise.
    def ==(other : String) : Bool
      to_slice == other.to_slice
    end
  end
end

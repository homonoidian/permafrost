require "./spec_helper"

# DISCLAIMER: Some of the tests below were written by an LLM
#
# Apparently LLMs still mess up simple math. For instance, this code had 3 + 1 + 1 = 4,
# so yay, whatever . . . AGI is coming, I guess, except it's not smarter AI, but
# stupider humans.

describe Pf::GraphemeSeln do
  # A + Combining Acute Accent = 1 grapheme, 3 bytes
  # \u{41}\u{301}
  complex_str = "\u{41}\u{301}\u{62}\u{63}" # "Ábc" (2 graphemes: [Á], [b], [c])
  ascii_str = "hello"

  novels = String.build do |io|
    File.open("spec/novels/01.txt") { |src| IO.copy(src, io) }
    File.open("spec/novels/02.txt") { |src| IO.copy(src, io) }
    File.open("spec/novels/03.txt") { |src| IO.copy(src, io) }
    File.open("spec/novels/04.txt") { |src| IO.copy(src, io) }
  end

  describe ".new" do
    it "handles ASCII strings (offset optimization)" do
      seln = Pf::GraphemeSeln.new(ascii_str)
      seln.size.should eq(5)
      seln.bytesize.should eq(5)
    end

    it "handles multibyte graphemes correctly" do
      seln = Pf::GraphemeSeln.new(complex_str)
      # "A\u{301}" is one grapheme, "b" is two, "c" is three.
      seln.size.should eq(3)
      seln.bytesize.should eq(5)
    end
  end

  describe "GraphemeView (via #ix)" do
    it "provides views into individual graphemes" do
      seln = Pf::GraphemeSeln.new(complex_str)
      views = seln.ix

      views.size.should eq(3)

      # Test first grapheme (A + combining accent)
      views[0].bytesize.should eq(3)
      views[0].to_s.should eq("\u{41}\u{301}")

      # Test GraphemeView equality with Char
      views[1].should eq('\u{62}') # 'b'
    end
  end

  describe "#select and #at" do
    it "slices by grapheme index" do
      seln = Pf::GraphemeSeln.new(complex_str) # [Á][b][c]
      sub = seln.select(1, 3)                  # [b][c]
      sub.to_s.should eq("\u{62}\u{63}")
      sub.size.should eq(2)
    end

    it "accesses specific graphemes" do
      seln = Pf::GraphemeSeln.new(complex_str)
      seln.at(0).to_s.should eq("\u{41}\u{301}")
    end
  end

  describe "#chomp" do
    it "removes trailing \n and \r\n" do
      Pf::GraphemeSeln.new("hi\u{000A}").chomp.to_s.should eq("hi")
      Pf::GraphemeSeln.new("hi\u{000D}\u{000A}").chomp.to_s.should eq("hi")
    end

    it "does not mangle multibyte strings without newlines" do
      Pf::GraphemeSeln.new(complex_str).chomp.to_s.should eq(complex_str)
    end
  end

  describe "Iteration and Segmentation" do
    it "partitions a string by a grapheme" do
      seln = Pf::GraphemeSeln.new("a\u{62}c") # abc
      before, at, after = seln.partition('\u{62}')

      before.to_s.should eq("a")
      at.to_s.should eq("b")
      after.to_s.should eq("c")
    end

    it "segments based on custom logic" do
      # Grouping by whether the grapheme is 'x'
      seln = Pf::GraphemeSeln.new("xxyy")
      segments = [] of {Bool, String}

      seln.each_segment(->(v : Pf::GraphemeView) { v == 'x' }) do |is_x, sub_seln|
        segments << {is_x, sub_seln.to_s}
      end

      segments.should eq([
        {true, "xx"},
        {false, "yy"},
      ])
    end
  end

  describe "Boundary behavior" do
    it "handles empty selections (cursors)" do
      seln = Pf::GraphemeSeln.new(ascii_str).before_start
      seln.empty?.should be_true
      seln.size.should eq(0)
    end

    it "shifts via succ and pred" do
      seln = Pf::GraphemeSeln.new(complex_str).at(0) # [Á]
      seln.succ.to_s.should eq("\u{62}")             # [b]
      seln.succ.pred.to_s.should eq("\u{41}\u{301}") # Back to [Á]
    end
  end

  describe "misc" do
    it "passes novels test" do
      novels.graphemes.should eq(Pf::GraphemeSeln.new(novels).ix.map(&.to_grapheme))
    end

    it "supports #detach" do
      parent = Pf::GraphemeSeln.new(novels)
      a = parent.select(100, 300)
      b = a.detach
      a.to_s.should eq(b.to_s)
      a.should_not eq(b)
      parent.should eq(a.expand)
      a.expand.should_not eq(b.expand)
    end
  end
end

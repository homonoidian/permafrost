require "./spec_helper"

def range(a, b)
  (a.to_u32...b.to_u32).to_a.shuffle!.to_pf_uset32
end

describe Pf::USet32 do
  it "supports #empty?" do
    set = Pf::USet32.new
    set.empty?.should be_true

    set = set.add(100)
    set.empty?.should be_false
  end

  it "reports correct #size" do
    Pf::USet32.new.size.should eq(0)
    Pf::USet32[1, 2, 3, 100, 200, 300, 10_000, 20_000, 30_000, 10_000_000].size.should eq(10)
  end

  it "reports #includes? correctly" do
    ns = {1, 2, 3, 100, 200, 300, 10_000, 20_000, 30_000, 10_000_000}.map(&.to_u32)
    set = Pf::USet32[*ns]
    set.includes?(0u32).should be_false
    ns.each do |n|
      set.includes?(n).should be_true
      set.includes?(n + 10).should be_false
    end
  end

  it "supports #each" do
    ns = {1, 2, 3, 100, 200, 300, 10_000, 20_000, 30_000, 10_000_000}.map(&.to_u32)
    set = Pf::USet32[*ns]
    set.each do |x|
      x.in?(ns).should be_true
    end
  end

  it "supports the #subset_of? family of methods" do
    xs = range(0, 100_000)
    xs.size.should eq(100_000)

    xs.subset_of?(xs).should be_true

    # Empty set
    xs.subset_of?(Pf::USet32[]).should be_false
    Pf::USet32[].subset_of?(xs).should be_true
    Pf::USet32[].proper_subset_of?(xs).should be_true
    Pf::USet32[].subset_of?(Pf::USet32[]).should be_true
    Pf::USet32[].proper_subset_of?(Pf::USet32[]).should be_false

    xs.superset_of?(xs).should be_true
    xs.proper_subset_of?(xs).should be_false
    xs.proper_superset_of?(xs).should be_false

    xs.add(101_000u32).subset_of?(xs).should be_false
    xs.add(101_000u32).superset_of?(xs).should be_true
    xs.add(101_000u32).proper_superset_of?(xs).should be_true

    xs.subset_of?(xs.add(101_000u32)).should be_true
    xs.proper_subset_of?(xs.add(101_000u32)).should be_true

    ys = range(10_000, 20_000)
    ys.subset_of?(xs).should be_true

    ys = range(100_000, 110_000)
    ys.subset_of?(xs).should be_false

    ys = range(100_000_000, 100_020_000)
    ys.subset_of?(xs).should be_false
  end

  it "supports #add?" do
    Pf::USet32[].add?(100).should eq({Pf::USet32[100], true})
    Pf::USet32[100].add?(100).should eq({Pf::USet32[100], false})
    Pf::USet32[1, 2, 3, 100, 200, 300, 1_000_000].add?(100).should eq({Pf::USet32[1, 2, 3, 100, 200, 300, 1_000_000], false})
    Pf::USet32[1, 2, 3, 100, 200, 300, 1_000_000].add?(101).should eq({Pf::USet32[1, 2, 3, 100, 101, 200, 300, 1_000_000], true})
  end

  it "supports union" do
    xs = range(0, 100_000)
    ys = range(0, 100_000)
    zs = range(100_000, 200_000)

    (xs | ys).should eq(xs)
    (ys | xs).should eq(xs)

    (ys | xs).should eq(ys)
    (xs | ys).should eq(ys)

    xs.hash.should eq(ys.hash)
    (xs | ys).hash.should eq(xs.hash)
    (xs | ys).hash.should eq(ys.hash)
    (xs | ys).should eq(xs)
    (xs | ys).should eq(ys)
    (xs | ys).should_not eq(zs)

    (xs | zs).should eq(ys | zs)
    (ys | zs).should eq(xs | ys | zs)

    (xs | zs).superset_of?(ys).should be_true
    (ys | zs).subset_of?(xs).should be_false
    (ys | zs).subset_of?(xs | zs).should be_true
    (ys | zs).proper_subset_of?(xs | zs).should be_false
    (ys | zs).proper_subset_of?(zs | xs | Pf::USet32[123_456_789]).should be_true

    (xs | ys | zs | Pf::USet32[123_456_789]).size.should eq(xs.size + zs.size + 1)
  end

  it "reports equality correctly" do
    # These tests are a big equality check anyway, so we're only testing
    # the empty cases here.
    (Pf::USet32[] == Pf::USet32[]).should be_true
    (Pf::USet32[1] == Pf::USet32[]).should be_false
    (Pf::USet32[] == Pf::USet32[1]).should be_false

    (Pf::USet32[1] == Pf::USet32[1]).should be_true
    (Pf::USet32[1] == Pf::USet32[2]).should be_false

    (Pf::USet32[1, 2, 100] == Pf::USet32[1]).should be_false
    (Pf::USet32[1, 2, 100] == Pf::USet32[2, 3, 100]).should be_false
    (Pf::USet32[1, 2, 100] == Pf::USet32[100, 2, 1]).should be_true
  end

  it "pretty prints" do
    Pf::USet32[1, 2, 3].pretty_inspect.should eq("Pf::USet32[1, 2, 3]")
  end

  it "can do bitmap sort" do
    xs = Pf::USet32.transaction do |commit|
      (0u32...1_000_000u32).to_a.shuffle!.each do |n|
        commit << n
      end
    end

    (0u32...1_000_000u32).to_a.should eq(xs.to_a)
  end

  it "supports additive identity" do
    {1u32, 2u32, 3u32}.sum { |x| Pf::USet32[x, x * 2] }.should eq(Pf::USet32[1, 2, 3, 4, 6])
  end

  it "reports #intersects? correctly" do
    ns = {1, 2, 3, 100, 200, 300, 10_000, 20_000, 30_000, 10_000_000}.map(&.to_u32)
    set = Pf::USet32[*ns]

    set.intersects?(set).should be_true
    set.intersects?(Pf::USet32[]).should be_false
    Pf::USet32[].intersects?(set).should be_false

    set.intersects?(Pf::USet32[1]).should be_true
    set.intersects?(Pf::USet32[1, 2]).should be_true
    set.intersects?(Pf::USet32[1, 3, 300]).should be_true
    set.intersects?(Pf::USet32[20_000]).should be_true
    set.intersects?(Pf::USet32[20_001]).should be_false
    set.intersects?(Pf::USet32[10_000, 20_000, 30_000]).should be_true
    set.intersects?(Pf::USet32[10_001, 20_000, 30_000]).should be_true
    set.intersects?(Pf::USet32[10_001, 20_001, 30_000]).should be_true
    set.intersects?(Pf::USet32[10_001, 20_001, 30_001]).should be_false
    set.intersects?(Pf::USet32[10_001, 20_001, 30_001, 10_000_000]).should be_true
    set.intersects?(Pf::USet32[10_001, 20_001, 30_001, 10_000_001]).should be_false

    xs = (0u32...100_000u32).to_pf_uset32
    ys = (100_000u32...200_000u32).to_pf_uset32

    xs.intersects?(ys).should be_false
    ys.intersects?(xs).should be_false
    xs.add(100_000).intersects?(ys).should be_true
    ys.add(99_999).intersects?(xs).should be_true
  end

  it "can intersect two sets properly" do
    xs = range(0, 100_000)
    ys = range(0, 100_000)
    zs = range(100_000, 200_000)

    (xs & ys).should eq(xs)
    (xs & ys).should eq(ys)

    a = range(100, 200)
    b = range(130_000, 230_000)

    ((xs | zs) & (a | b)).should eq(a | (zs & b))
  end

  it "satisfies set properties" do
    a = range(0, 10000) | range(20000, 30000) | range(50000, 60000)
    a_copy = range(0, 10000) | range(20000, 30000) | range(50000, 60000)
    b = range(5000, 15000) | range(25000, 35000) | range(55000, 65000)
    c = range(10000, 20000) | range(30000, 40000)

    # Commutativity.
    (a | b).should eq(b | a)
    (a & b).should eq(b & a)

    # Associativity.
    ((a | b) | c).should eq(a | (b | c))
    ((a & b) & c).should eq(a & (b & c))

    # Idempotence
    (a | a_copy).should eq(a)
    (a & a_copy).should eq(a)

    # Absorption
    (a | (a & b)).should eq(a)
    (a & (a | b)).should eq(a)

    # Distributivity
    (a & (b | c)).should eq((a & b) | (a & c))
    (a | (b & c)).should eq((a | b) & (a | c))

    (a - Pf::USet32[]).should eq(a)
    (a - a_copy).should eq(Pf::USet32[])

    # De Morgan's law
    (a - (b & c)).should eq((a - b) | (a - c))
    (a - (b | c)).should eq((a - b) & (a - c))

    ((a | b) - c).should eq((a - c) | (b - c))
    ((a & b) - c).should eq((a - c) & (b - c))

    (a - b).subset_of?(a).should be_true

    (a & b).subset_of?(a).should be_true
    (a & b).subset_of?(b).should be_true

    a.subset_of?(a | b).should be_true
    b.subset_of?(a | b).should be_true

    ((b - a) & a).should eq(Pf::USet32[])

    ((a & b) | (a - b)).should eq(a)
    ((a & b) & (a - b)).should eq(Pf::USet32[])
  end

  it "supports #delete" do
    set = Pf::USet32[100, 200]
    set.delete(100).empty?.should be_false
    set.delete(100).delete(200).empty?.should be_true
    set.delete(200).delete(100).empty?.should be_true

    xs = range(0, 10_000)
    ys = range(10_000, 20_000)

    (xs | ys).delete(10_000).should eq(xs | ys.delete(10_000))

    u = xs | ys
    ys_copy = range(10_000, 20_000) # different order due to shuffle in range()

    xs_copy = ys_copy.reduce(u) { |memo, y| memo.delete(y) }
    xs_copy.should eq(xs)
    xs_copy.should eq(u - ys)

    ys_copy = xs_copy.reduce(u) { |memo, x| memo.delete(x) }
    ys_copy.should eq(ys)
    ys_copy.should eq(u - xs)
  end

  it "reports presence correctly in #add?" do
    Pf::USet32.new.add?(5).should eq({Pf::USet32[5], true})
    Pf::USet32[5].add?(100).should eq({Pf::USet32[5, 100], true})
    Pf::USet32[5, 100].add?(5).should eq({Pf::USet32[5, 100], false})
    Pf::USet32[5, 100].add?(100).should eq({Pf::USet32[5, 100], false})
    Pf::USet32[5, 100].add?(100_000).should eq({Pf::USet32[5, 100, 100_000], true})
    Pf::USet32[5, 100, 100_000].add?(100_000).should eq({Pf::USet32[5, 100, 100_000], false})
  end
end

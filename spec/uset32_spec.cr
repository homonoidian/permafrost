require "./spec_helper"

describe Pf::USet32 do
  it "supports #empty?" do
    set = Pf::USet32.new
    set.empty?.should be_true

    set = set.add(100)
    set.empty?.should be_false

    # set = set.delete(200)
    # set.empty?.should be_false

    # set = set.delete(100)
    # set.empty?.should be_true
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
    xs = (0u32...100_000u32).to_a.shuffle!.to_pf_uset32
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

    ys = (10_000u32...20_000u32).to_a.shuffle!.to_pf_uset32
    ys.subset_of?(xs).should be_true

    ys = (100_000u32...110_000u32).to_a.shuffle!.to_pf_uset32
    ys.subset_of?(xs).should be_false

    ys = (100_000_000u32...100_020_000u32).to_a.shuffle!.to_pf_uset32
    ys.subset_of?(xs).should be_false
  end

  it "supports #add?" do
    Pf::USet32[].add?(100).should eq({Pf::USet32[100], true})
    Pf::USet32[100].add?(100).should eq({Pf::USet32[100], false})
    Pf::USet32[1, 2, 3, 100, 200, 300, 1_000_000].add?(100).should eq({Pf::USet32[1, 2, 3, 100, 200, 300, 1_000_000], false})
    Pf::USet32[1, 2, 3, 100, 200, 300, 1_000_000].add?(101).should eq({Pf::USet32[1, 2, 3, 100, 101, 200, 300, 1_000_000], true})
  end

  it "supports union" do
    xs = (0u32...100_000u32).to_a.shuffle!.to_pf_uset32
    ys = (0u32...100_000u32).to_a.shuffle!.to_pf_uset32
    zs = (100_000u32...200_000u32).to_a.shuffle!.to_pf_uset32

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
  end
end

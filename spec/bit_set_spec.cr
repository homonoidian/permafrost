require "./spec_helper"

# DISCLAIMER: The tests below are written by ChatGPT. I don't like writing tests!

describe Pf::BitSet32 do
  it "can create an empty set" do
    set = Pf::BitSet32.empty
    set.empty?.should be_true
    set.size.should eq(0)
  end

  it "can create a set from values" do
    set = Pf::BitSet32[1, 3, 5]
    set.empty?.should be_false
    set.size.should eq(3)
    set.includes?(1).should be_true
    set.includes?(2).should be_false
    set.includes?(5).should be_true
  end

  it "adds and deletes elements" do
    set = Pf::BitSet32.empty
    set = set.add(7)
    set.includes?(7).should be_true
    set.size.should eq(1)

    set = set.delete(7)
    set.includes?(7).should be_false
    set.size.should eq(0)
  end

  it "does not add elements out of range" do
    set = Pf::BitSet32.empty
    set = set.add(32)
    set.size.should eq(0)
  end

  it "calculates mex correctly" do
    set = Pf::BitSet32[0, 1, 3]
    set.mex.should eq(2)

    set = Pf::BitSet32.empty
    set.mex.should eq(0)

    full_set = Pf::BitSet32.new(UInt32::MAX)
    full_set.mex.should eq(32)
  end

  it "computes rank correctly" do
    set = Pf::BitSet32[2, 4, 7]
    set.rank(0).should eq(0)
    set.rank(2).should eq(0)
    set.rank(3).should eq(1)
    set.rank(7).should eq(2)
    set.rank(8).should eq(3)
  end

  it "performs union, intersection, difference" do
    a = Pf::BitSet32[1, 2, 3]
    b = Pf::BitSet32[3, 4, 5]

    (a & b).should eq(Pf::BitSet32[3])
    (a | b).should eq(Pf::BitSet32[1, 2, 3, 4, 5])
    (a ^ b).should eq(Pf::BitSet32[1, 2, 4, 5])
  end

  it "computes complement correctly" do
    set = Pf::BitSet32[0, 31]
    comp = set.complement
    comp.includes?(0).should be_false
    comp.includes?(31).should be_false
    comp.includes?(1).should be_true
    comp.size.should eq(30)
  end

  it "iterates values correctly" do
    values = [] of UInt32
    Pf::BitSet32[1, 3, 5].each do |v|
      values << v
    end
    values.should eq([1, 3, 5])
  end

  it "iterates with index correctly" do
    values = [] of UInt32
    indices = [] of Int32
    Pf::BitSet32[2, 4].each_with_index do |v, i|
      values << v
      indices << i
    end
    values.should eq([2, 4])
    indices.should eq([0, 1])
  end

  it "handles lt and gte masks correctly" do
    set = Pf::BitSet32[1, 3, 5, 7]
    set.lt(5).should eq(Pf::BitSet32[1, 3])
    set.gte(3).should eq(Pf::BitSet32[3, 5, 7])
  end

  it "detects full set correctly" do
    full_set = Pf::BitSet32.new(UInt32::MAX)
    full_set.full?.should be_true
    Pf::BitSet32.empty.full?.should be_false
  end
end

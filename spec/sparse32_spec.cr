require "./spec_helper"

include Pf::Core

describe Pf::Core::Sparse32 do
  it "should grow when capacity is exceeded all the way to 32" do
    ary = Sparse32(Int32).new
    ary.empty?.should be_true
    32.times do |n|
      ary = {true, false}.sample ? ary.with!(n, n * 2) : ary.with(n, n * 2)
    end
    ary.empty?.should be_false
    ary.size.should eq(32)
    s = 0
    ary.each do |i|
      s += i
    end
    s.should eq((0...32).sum { |n| n*2 })
  end

  it "should allow to add randomly in 0...32, remove randomly in 0...32, keep track of size" do
    indices = (0...32).to_a
    ary = Sparse32(Int32).new
    ary.empty?.should be_true
    32.times do |i|
      indices.shuffle.each { |n| ary = {true, false}.sample ? ary.with!(n, i) : ary.with(n, i) }
    end
    ary.empty?.should be_false
    ary.size.should eq(32)
    s = 0
    ary.each do |i|
      s += i
    end
    s.should eq(32 * 31)
    sums = [] of Int32
    indices.shuffle.each do |n|
      ary = {true, false}.sample ? ary.without!(n) : ary.without(n)
      s = 0
      ary.each do |i|
        s += i
      end
      sums << s
    end
    sums.sum.should eq(15376)
    ary.size.should eq(0)
    ary.empty?.should be_true
    ary.each do |i|
      raise "error"
    end
  end

  it "should raise IndexError if index is out of bounds in with[!], at?, without[!]" do
    xs = Sparse32(Int32).new
    xs.with!(1, 100)
    xs.with!(2, 200)
    xs.with!(3, 300)
    expect_raises(IndexError) { xs.at?(100) }
    expect_raises(IndexError) { xs.at?(-100) }
    expect_raises(IndexError) { xs.with(100, 10) }
    expect_raises(IndexError) { xs.with!(-100, 10) }
    expect_raises(IndexError) { xs.without(100) }
    expect_raises(IndexError) { xs.without!(-100) }
  end

  it "should support nth" do
    xs = Sparse32(Int32).new
    xs.with!(0, 100)
    xs.with!(10, 200)
    xs.with!(20, 300)
    xs.nth?(0).should eq(100)
    xs.nth?(1).should eq(200)
    xs.nth?(2).should eq(300)
    xs.nth?(3).should be_nil
    xs.nth?(10).should be_nil

    expect_raises(IndexError) { xs.nth?(-1) }
    expect_raises(IndexError) { xs.nth?(300) }
  end
end

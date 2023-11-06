require "./spec_helper"

include Pf::Core

describe Pf::Core::Sparse32 do
  it "should allocate capacity-2 initially" do
    ary = Sparse32(Int32).new
    Sparse32::CAPS[ary.size].should eq(2)
  end

  it "should grow when capacity is exceeded all the way to 32" do
    ary = Sparse32(Int32).new
    32.times do |n|
      ary = ary.put(n, n * 2)
    end
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
    32.times do |i|
      indices.shuffle.each { |n| ary = ary.put(n, i) }
    end
    ary.size.should eq(32)
    s = 0
    ary.each do |i|
      s += i
    end
    s.should eq(32 * 31)
    sums = [] of Int32
    indices.shuffle.each do |n|
      ary = ary.delete(n)
      s = 0
      ary.each do |i|
        s += i
      end
      sums << s
    end
    sums.sum.should eq(15376)
    ary.size.should eq(0)
    ary.each do |i|
      raise "error"
    end
  end

  it "should support #dup" do
    ary = Sparse32(Int32).new
    5.times do |n|
      ary = ary.put(n, n * 2)
    end
    ary2 = ary.dup
    5.times do |n|
      ary = ary.put(n, n * 3)
    end
    s1 = 0
    ary.each do |i|
      s1 += i
    end
    s2 = 0
    ary2.each do |i|
      s2 += i
    end
    s1.should eq((0...5).sum { |n| n * 3 })
    s2.should eq((0...5).sum { |n| n * 2 })
  end
end

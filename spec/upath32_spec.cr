require "./spec_helper"

describe Pf::UPath32 do
  it "supports #append, #prior, equality" do
    y = Pf::UPath32[100u32]
    y = y.append(30u32)
    y = y.append(20u32)
    y = y.append(5u32)
    y = y.append(5u32)
    y = y.append(3u32)
    y = y.append(8u32)
    y = y.append(15u32)
    y = y.append(4u32)
    y = y.append(0u32)
    y = y.append(0u32)
    y = y.append(7u32)
    y = y.append(3u32)
    y = y.append(12u32)
    y = y.prior.append(56u32).prior.prior.prior.append(10u32)
    y.should eq(Pf::UPath32[100, 30, 20, 5, 5, 3, 8, 15, 4, 0, 0, 10])
  end

  it "supports equality with different histories" do
    a = Pf::UPath32[100u32]
    b = Pf::UPath32[100u32, 200u32].prior
    a.should eq(b)

    a = Pf::UPath32[100u32, 50u32, 12345u32].prior
    b = Pf::UPath32[100u32, 50u32]
    a.should eq(b)

    a = Pf::UPath32[1234567u32, 456789u32].prior
    b = Pf::UPath32[1234567u32]
    a.should eq(b)
  end

  it "supports fetch" do
    path = Pf::UPath32[100, 30, 20, 5, 5, 3, 8, 15, 4, 0, 0, 10]
    path.each_with_index do |step, index|
      path[index].should eq(step)
    end
  end

  # DISCLAIMER: Some of the tests below were written by an LLM

  it "constructs empty and singleton paths" do
    path = Pf::UPath32[]
    path.size.should eq(0)
    path.last?.should be_nil
    expect_raises(IndexError) { path.last }

    singleton = Pf::UPath32[42]
    singleton.size.should eq(1)
    singleton.last?.should eq(42)
    singleton.last.should eq(42)
    singleton[0].should eq(42)
    singleton[-1].should eq(42)
    singleton[0]?.should eq(42)
    singleton[1]?.should be_nil
  end

  it "appends steps and traverses prior" do
    path = Pf::UPath32[]
    steps = (1u32..12u32).to_a # more than dense capacity (10) to cross into sparse
    steps.each do |s|
      path = path.append(s)
    end

    path.size.should eq(12)
    path.last?.should eq(12)
    path[-1].should eq(12)
    path[0].should eq(1)
    path[11].should eq(12)
    path[12]?.should be_nil

    # Walk backwards using prior
    current = path
    collected = [] of UInt32
    12.times do
      collected << current.last
      current = current.prior
    end
    collected.should eq(steps.reverse)
    current.size.should eq(0)
  end

  it "supports each and enumerables" do
    path = Pf::UPath32[]
    steps = [5, 9, 1, 8, 7, 3, 6, 4, 2, 0, 11] of UInt32 # crosses dense capacity
    steps.each { |s| path = path.append(s) }

    collected = [] of UInt32
    path.each { |x| collected << x }
    collected.should eq(steps)

    path.map(&.to_s).should eq(steps.map(&.to_s))
    path.select(&.even?).should eq(steps.select(&.even?))
    path.any?(&.zero?).should be_true
    path.all?(&.is_a?(UInt32)).should be_true
  end

  it "supports indexing with positive and negative indices" do
    path = Pf::UPath32[]
    steps = (10u32..15u32).to_a
    steps.each { |s| path = path.append(s) }

    steps.each_with_index do |s, i|
      path[i].should eq(s)
      path[i]?.should eq(s)
      path[i - steps.size].should eq(s)
    end

    expect_raises(IndexError) { path[steps.size] }
    path[steps.size]?.should be_nil
    expect_raises(IndexError) { path[-steps.size - 1] }
  end

  it "supports equality and hash consistency" do
    steps = (1u32..15u32).to_a
    path1 = Pf::UPath32[]
    path2 = Pf::UPath32[]
    steps.each do |s|
      path1 = path1.append(s)
    end

    # Build the same logical path differently
    path2 = Pf::UPath32[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    (11u32..15u32).each { |s| path2 = path2.append(s) }

    path1.should eq(path2)
    path1.hash.should eq(path2.hash)

    # Mutating via persistence produces a distinct path
    shorter = path1.prior
    shorter.should_not eq(path1)
    shorter.hash.should_not eq(path1.hash)

    # Use as hash keys
    table = {} of Pf::UPath32 => String
    table[path1] = "full"
    table[shorter] = "short"

    table[path1].should eq("full")
    table[path2].should eq("full")
    table[shorter].should eq("short")
  end

  it "handles last? and prior on dense-to-sparse transition" do
    path = Pf::UPath32[]
    steps = (0u32..15u32).to_a
    steps.each { |s| path = path.append(s) }

    # Ensure last? is always correct
    path.last?.should eq(15)

    # Walk prior until empty
    current = path
    collected = [] of UInt32
    16.times do
      collected << current.last
      current = current.prior
    end
    collected.should eq(steps.reverse)
    current.size.should eq(0)
  end
end

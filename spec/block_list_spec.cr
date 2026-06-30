require "./spec_helper"

# DISCLAIMER: Some of the tests below were written by an LLM

describe Pf::BlockList do
  groceries = [
    "milk",
    "eggs",
    "bread",
    "butter",
    "cheese",
    "apples",
    "bananas",
    "carrots",
    "coffee", # 9th item crosses the block boundary
  ]

  it "supports append, prior, last" do
    list = Pf::BlockList(String).new

    groceries.each_with_index do |item, idx|
      list = list.append(item)
      list.size.should eq(idx + 1)
      list.last.should eq(item)
    end

    reversed = groceries.reverse
    current = list

    reversed.each do |item|
      current.last.should eq(item)
      current = current.prior
    end

    current.size.should eq(0)
  end

  it "supports fetch" do
    list = Pf::BlockList(String).new
    groceries.each { |item| list = list.append(item) }

    groceries.each_with_index do |item, idx|
      list[idx].should eq(item)
    end

    expect_raises(IndexError) { list[groceries.size] }
  end

  it "supports reverse_each" do
    list = Pf::BlockList(String).new
    groceries.each { |item| list = list.append(item) }

    collected = [] of String
    list.reverse_each { |item| collected << item }

    collected.should eq(groceries.reverse)
  end

  it "supports each" do
    list = Pf::BlockList(String).new
    groceries.each { |item| list = list.append(item) }

    collected = [] of String
    list.each { |item| collected << item }

    collected.should eq(groceries)
  end

  it "supports enumerable methods" do
    list = Pf::BlockList(String).new
    groceries.each { |item| list = list.append(item) }

    list.map(&.upcase).should eq(groceries.map(&.upcase))
    list.select(&.includes?("e")).should eq(groceries.select(&.includes?("e")))
    list.any?(&.includes?("coffee")).should be_true
    list.all?(&.is_a?(String)).should be_true
  end

  it "passes smoke test" do
    tokenlist = Pf::BlockList(String).new
    expected = Set(String).new

    novel = File.read("#{__DIR__}/novels/02.txt")
    tokens = novel.split(/\s+/, remove_empty: true) # ~200k tokens
    {% unless flag?(:release) %}
      tokens = tokens[...50_000]
    {% end %}

    tokens.each do |token|
      expected << token
      next if tokenlist.rincludes?(token)
      tokenlist = tokenlist.append(token)
    end

    tokenlist.to_set.should eq(expected)
  end

  it "supports equality and hashing across block boundaries" do
    list1 = Pf::BlockList(String).new
    groceries.each { |item| list1 = list1.append(item) }

    # Build the same logical list in a different way
    list2 = Pf::BlockList(String).new
    groceries[0, 4].each { |item| list2 = list2.append(item) }
    groceries[4, 5].each { |item| list2 = list2.append(item) }

    list1.should eq(list2)
    list1.hash.should eq(list2.hash)

    # Ensure prior/append round-trips preserve equality
    list3 = list1.prior.append("coffee")
    list3.should eq(list1)
    list3.hash.should eq(list1.hash)

    # Use BlockList as hash keys
    table = {} of Pf::BlockList(String) => Int32
    table[list1] = 1

    table.has_key?(list2).should be_true
    table[list2].should eq(1)

    # Mutating structure via persistence should produce a distinct key
    shorter = list1.prior
    shorter.should_not eq(list1)

    table[shorter] = 2
    table[list1].should eq(1)
    table[shorter].should eq(2)
  end
end

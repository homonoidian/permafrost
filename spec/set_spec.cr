require "./spec_helper"

describe Pf::Set do
  describe "instantiation" do
    it "supports .new" do
      set = Pf::Set(Int32).new
      set.empty?.should be_true
    end

    it "supports .new with enumerable" do
      set = Pf::Set.new([1, 2, 3])
      set.size.should eq(3)
      set.empty?.should be_false
      set.to_set.should eq(Set{1, 2, 3})
    end

    it "supports .[]" do
      set = Pf::Set[1, 2, 3]
      set.to_set.should eq(Set{1, 2, 3})

      set = Pf::Set[1, "Hello", 3, true]
      set.to_set.should eq(Set{1, "Hello", 3, true})
    end
  end

  describe "methods" do
    it "supports #size" do
      set = Pf::Set(Int32).new
      set.size.should eq(0)

      set = set.add(1)
      set.size.should eq(1)

      set = set.add(2)
      set.size.should eq(2)

      10.times do |n|
        set = set.add(n)
      end
      set.size.should eq(10)
    end

    it "supports #empty?" do
      set = Pf::Set(Int32).new
      set.empty?.should be_true

      set = set.add(1)
      set.empty?.should be_false

      set = set.add(2)
      set.empty?.should be_false
    end

    it "supports #includes?" do
      set = Pf::Set[1, 2, 3]

      1.in?(set).should be_true
      2.in?(set).should be_true
      3.in?(set).should be_true
      100.in?(set).should be_false
      "foobar".in?(set).should be_false
    end

    it "supports #each" do
      set = Pf::Set(Int32).new
      set.each { |_| true.should be_false }
      set.add(100).each { |v| v.should eq(100) }
      set.add(100).add(200).each { |v| {100, 200}.should contain(v) }
    end

    it "supports #fmap" do
      set = Pf::Set[1, 2, 3]
      set.fmap(&.succ).should eq(Pf::Set[2, 3, 4])
      set.fmap(&.succ.to_s).should eq(Pf::Set["2", "3", "4"])
      set.fmap(&.itself).should be(set)
      set.fmap(&.succ.pred).should be(set)
    end

    it "supports #select, #reject, #+ (concat), #&" do
      evens = (0...10).to_pf_set.select(&.even?)
      odds = (0...10).to_pf_set.reject(&.even?)

      evens.should eq(Pf::Set[0, 2, 4, 6, 8])
      odds.should eq(Pf::Set[1, 3, 5, 7, 9])

      (evens & odds).empty?.should be_true
      (evens & odds.add(2).add(4)).should eq(Pf::Set[2, 4])
      (evens + odds).should eq((0...10).to_pf_set)

      a = Pf::Set(Int32).new
      b = Pf::Set[1, 2, 3]
      (a + b).should be(b)
      a.concat(b).should be(b)

      a = Pf::Set[1, 2, 3]
      b = Pf::Set(Int32).new
      (a + b).should be(a)
      a.concat(b).should be(a)

      a = Pf::Set[1, 2, 3]
      b = Pf::Set[1, 2, 3]
      (a + b).should be(a)
      a.concat(b).should be(a)
      (b + a).should be(b)
      b.concat(a).should be(b)

      xs = Pf::Set[2, 4, 6]
      xs.select(&.even?).should be(xs)
      xs.reject(&.odd?).should be(xs)
    end

    it "supports #add, #delete" do
      numbers = (0...100).to_pf_set # <- add()s under the hood
      numbers.size.should eq(100)
      numbers.sum.should eq(4950)
      50.in?(numbers).should be_true

      del = numbers.reduce(numbers) { |set, n| set.delete(n) }
      del.size.should eq(0)
      del.empty?.should be_true

      set1 = (0...100).to_pf_set
      set1.reduce(set1) { |set, n| set.add(n) }.should be(set1)
    end

    it "supports #same?" do
      set1 = Pf::Set[1, 2, 3]
      set2 = set1.add(1).add(2).add(3)
      set1.same?(set2) # => true
    end

    it "supports #===" do
      reds = Pf::Set["red", "pink", "violet"]
      blues = Pf::Set["blue", "azure", "violet"]
      both = red = blue = false

      case "violet"
      when reds & blues
        both = true
      when reds
        red = true
      when blues
        blue = true
      end

      both.should be_true
      red.should be_false
      blue.should be_false
    end

    it "supports #hash" do
      set1 = Pf::Set[1, 2, 3]
      set2 = Pf::Set[1, 2, 3]
      set3 = Pf::Set[1, 2, 3, 4, 5]
      set4 = Pf::Set[1, 2, "3"]
      set5 = Set{1, 2, 3}
      map = Pf::Map(Int32, Nil).new.assoc(1, nil).assoc(2, nil).assoc(3, nil)

      set1.hash.should eq(set2.hash)
      set1.hash.should_not eq(set3.hash)
      set1.hash.should_not eq(set4.hash)
      set1.hash.should_not eq(set5.hash)
      set1.hash.should_not eq(map.hash)
    end
  end

  it "should raise resolved error if commit is retained" do
    cobj = nil
    map = Pf::Set[1, 2, 3]
    map.transaction do |commit|
      cobj = commit
      commit.add(4)
    end
    3.in?(cobj.not_nil!).should be_true
    4.in?(cobj.not_nil!).should be_true
    100.in?(cobj.not_nil!).should be_false
    expect_raises(Pf::ResolvedError) { cobj.not_nil!.add(56) }
    expect_raises(Pf::ResolvedError) { cobj.not_nil!.delete(4) }
    expect_raises(Pf::ResolvedError) { cobj.not_nil!.resolve }
  end

  it "should raise readonly error if commit is passed to another fiber" do
    went_through_chain = Channel(Bool).new
    chan_add = Channel(Pf::Set::Commit(Int32)).new
    chan_delete = Channel(Pf::Set::Commit(Int32)).new
    chan_resolve = Channel(Pf::Set::Commit(Int32)).new

    spawn do
      commit = chan_add.receive
      begin
        commit.add(123)
        went_through_chain.send(false)
      rescue Pf::ReadonlyError
        chan_delete.send(commit)
      end
    end

    spawn do
      commit = chan_delete.receive
      begin
        commit.delete(456)
        went_through_chain.send(false)
      rescue Pf::ReadonlyError
        chan_resolve.send(commit)
      end
    end

    spawn do
      commit = chan_resolve.receive
      begin
        commit.resolve
        went_through_chain.send(false)
      rescue Pf::ReadonlyError
        went_through_chain.send(true)
      end
    end

    set = Pf::Set[1, 2, 3]
    set.transaction do |commit|
      chan_add.send(commit)
      went_through_chain.receive.should be_true
    end
  end

  it "should run the example from #transaction" do
    set1 = Pf::Set[1, 2, 3]
    set2 = set1.transaction do |commit|
      commit.add(4)
      commit.delete(2) if 4.in?(commit)
      if 2.in?(commit)
        commit.delete(4)
        commit.add(6)
      else
        commit.delete(4)
        commit.add(2)
        commit.add(5)
      end
    end

    set1.should eq(Pf::Set[1, 2, 3])
    set2.should eq(Pf::Set[1, 2, 3, 5])

    set3 = set1.transaction do |commit|
    end

    set1.should eq(Pf::Set[1, 2, 3])
    set3.should be(set1)
  end
end

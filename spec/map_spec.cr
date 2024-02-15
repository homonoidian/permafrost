require "./spec_helper"

struct Collider
  def initialize(@val : String)
  end

  def_equals @val

  def hash
    1u64
  end
end

record Info1, first_name : String, last_name : String
record Info2, first_name : String, last_name : String do
  include Pf::Eq
end

record Point1, x : Int32, y : Int32 do
  def succ
    copy_with(x + 1, y + 1)
  end

  def pred
    copy_with(x - 1, y - 1)
  end
end

record Point2, x : Int32, y : Int32 do
  include Pf::Eq

  def succ
    copy_with(x + 1, y + 1)
  end

  def pred
    copy_with(x - 1, y - 1)
  end
end

describe Pf::Map do
  describe "internals" do
    it "supports correct size, each, find, assoc, dissoc for empty map" do
      empty = Pf::Map(String, Int32).new
      empty.size.should eq(0)
      empty.each { |k, v| true.should be_false }
      empty["foo"]?.should be_nil
      "foo".in?(empty).should be_false

      br = empty.assoc("bar", 100) # transition into Mapping
      br.should_not be(empty)
      br["bar"]?.should eq(100)
      empty["bar"]?.should eq(nil)

      upd = empty.update("foo", 100, &.succ)
      upd["foo"]?.should eq(100)
      empty["foo"]?.should be_nil

      empty.dissoc("foo").should be(empty)
    end

    it "supports correct size, each, find, assoc, dissoc for single mapping" do
      single = Pf::Map[foo: 123]
      single.size.should eq(1)
      single.each do |k, v|
        k.should eq("foo")
        v.should eq(123)
      end
      single["foo"]?.should eq(123)
      single["bar"]?.should be_nil
      "foo".in?(single).should be_true
      "bar".in?(single).should be_false

      br1 = single.assoc("bar", 200) # transition into Row
      br1.should_not be(single)

      br1["foo"]?.should eq(123)
      br1["bar"]?.should eq(200)

      single["foo"]?.should eq(123)
      single["bar"]?.should be_nil

      single.assoc("foo", 123).should be(single)
      upd = single.assoc("foo", 456)
      upd.should_not be(single)
      upd["foo"]?.should eq(456)
      single["foo"]?.should eq(123)

      single.update("foo", 123, &.itself).should be(single)
      upd = single.update("foo", 123, &.succ)
      upd.should_not be(single)
      upd["foo"]?.should eq(124)

      del = upd.dissoc("foo")
      del.size.should eq(0)
      del.each { |k, v| true.should be_false }

      upd["foo"]?.should eq(124)
      upd.dissoc("bar").should be(upd)
    end

    it "supports correct size, each, find, assoc, update, dissoc for collisions" do
      map = Pf::Map(Collider, String).new
      map = map.assoc(Collider.new("John"), "Doe")
      map = map.assoc(Collider.new("Samantha"), "Lee")
      map.size.should eq(2)

      map[Collider.new("John")]?.should eq("Doe")
      map[Collider.new("Samantha")]?.should eq("Lee")

      map = map.assoc(Collider.new("Samuel"), "Bar")
      map[Collider.new("John")]?.should eq("Doe")
      map[Collider.new("Samantha")]?.should eq("Lee")
      map[Collider.new("Samuel")]?.should eq("Bar")

      map.each do |k, v|
        {Collider.new("John"), Collider.new("Samantha"), Collider.new("Samuel")}.should contain(k)
        {"Doe", "Lee", "Bar"}.should contain(v)
      end

      map.assoc(Collider.new("Samuel"), "Bar").should be(map)
      upd = map.assoc(Collider.new("Samuel"), "Bee")
      upd.should_not be(map)
      upd[Collider.new("John")]?.should eq("Doe")
      upd[Collider.new("Samantha")]?.should eq("Lee")
      upd[Collider.new("Samuel")]?.should eq("Bee")

      map2 = Pf::Map(Collider, Int32).new
      map2 = map2.assoc(Collider.new("John"), 10)
      map2 = map2.assoc(Collider.new("Bob"), 20)

      upd = map2.update(Collider.new("John"), 100, &.succ)
      upd.should_not be(map2)
      upd.should eq(
        Pf::Map
          .assoc(Collider.new("John"), 11)
          .assoc(Collider.new("Bob"), 20)
      )

      upd2 = upd.update(Collider.new("Barbara"), 100, &.succ)
      upd2.should eq(
        Pf::Map
          .assoc(Collider.new("John"), 11)
          .assoc(Collider.new("Bob"), 20)
          .assoc(Collider.new("Barbara"), 100)
      )

      upd2[Collider.new("John")]?.should eq(11)
      upd2[Collider.new("Bob")]?.should eq(20)
      upd2[Collider.new("Barbara")]?.should eq(100)

      upd[Collider.new("John")]?.should eq(11)
      upd[Collider.new("Bob")]?.should eq(20)
      upd[Collider.new("Barbara")]?.should be_nil

      del = upd2.dissoc(Collider.new("John"))
      del[Collider.new("John")]?.should be_nil
      del[Collider.new("Bob")]?.should eq(20)
      del[Collider.new("Barbara")]?.should eq(100)
    end
  end

  describe "user-facing" do
    it "supports #keys" do
      map = Pf::Map[foo: 10, bar: 20]
      map.keys.to_set.should eq(Set{"foo", "bar"})
    end

    it "supports #values" do
      map = Pf::Map[foo: 10, bar: 20]
      map.values.to_set.should eq(Set{10, 20})
    end

    it "supports #includes?" do
      map = Pf::Map[foo: 100, bar: 200]
      "foo".in?(map).should be_true
      "bar".in?(map).should be_true
      "baz".in?(map).should be_false
      100.in?(map).should be_false
      {"foo", 100}.in?(map).should be_false

      map = Pf::Map[foo: 100, bar: nil]
      "foo".in?(map).should be_true
      "bar".in?(map).should be_true
      "baz".in?(map).should be_false

      map.has_key?("foo").should be_true
      map.has_key?("bar").should be_true
      map.has_key?("baz").should be_false
    end

    it "supports #[]?" do
      map = Pf::Map[foo: 10, bar: 20]
      map["foo"]?.should eq(10)
      map["bar"]?.should eq(20)
      map["baz"]?.should be_nil
    end

    it "supports #[]? (dig)" do
      map = Pf::Map[foo: Pf::Map[bar: {100 => Pf::Map[baz: "Yay!"]}]]
      map["foo", "bar", 100, "baz"]?.should eq("Yay!")
      map["foo", "bar", 200]?.should be_nil
    end

    it "supports #[]" do
      map = Pf::Map[foo: 10]
      map["foo"].should eq(10)
      expect_raises(KeyError, "Missing map key: \"bar\"") do
        map["bar"]
      end
    end

    it "supports #[] (dig)" do
      map = Pf::Map[foo: Pf::Map[bar: {100 => Pf::Map[baz: "Yay!"]}]]
      map["foo", "bar", 100, "baz"].should eq("Yay!")
      expect_raises(KeyError, "Missing hash key: 200") do
        map["foo", "bar", 200]
      end
      expect_raises(KeyError, "Map value not diggable for key: \"boo\"") do
        map["foo", "boo", 200, "baz"]
      end
      expect_raises(KeyError, "Missing map key: \"hello\"") do
        map["hello"]
      end
      expect_raises(KeyError, "Map value not diggable for key: \"hello\"") do
        map["hello", "foo"]
      end
      map2 = {"foo" => Pf::Map[bar: Pf::Map[baz: 200]]}
      map2.dig("foo", "bar", "baz").should eq(200)
      expect_raises(KeyError, "Map value not diggable for key: \"boo\"") do
        map2.dig("foo", "bar", "boo")
      end
    end

    it "supports #assoc" do
      map = Pf::Map(String, Int32).new

      branch1 = map.assoc("foo", 100)
      branch2 = map.assoc("foo", 200)

      map = map.assoc("bar", 300)

      map["foo"]?.should be_nil
      map["bar"]?.should eq(300)

      branch1["foo"]?.should eq(100)
      branch1["bar"]?.should be_nil

      branch2["foo"]?.should eq(200)
      branch2["bar"]?.should be_nil
    end

    it "supports #update" do
      map = Pf::Map[foo: 100, bar: 200]
      map.update("foo", 0, &.succ).should eq(Pf::Map[foo: 101, bar: 200])
      map.update("baz", 0, &.succ).should eq(Pf::Map[foo: 100, bar: 200, baz: 0])
    end

    it "supports #dissoc" do
      map = Pf::Map[foo: 100, bar: 200]

      branch1 = map.dissoc("foo")
      branch2 = map.dissoc("bar")

      map["foo"]?.should eq(100)
      map["bar"]?.should eq(200)

      branch1["foo"]?.should be_nil
      branch1["bar"]?.should eq(200)

      branch2["foo"]?.should eq(100)
      branch2["bar"]?.should be_nil
    end

    it "supports #merge (k, v)" do
      a = Pf::Map[foo: 100, bar: 200]
      b = Pf::Map[foo: 200, baz: 500]
      a.merge(b).should eq(Pf::Map[foo: 200, bar: 200, baz: 500])

      a = Pf::Map[foo: 100, bar: 200]
      b = Pf::Map[foo: 100, bar: 200]
      a.merge(b).should be(a)
      b.merge(a).should be(b)
    end

    it "supports #merge (k2, v2)" do
      a = Pf::Map[foo: 100, bar: 200]
      b = Pf::Map[foo: "hello", baz: true, boo: 500]

      map = a.merge(b)
      map.should eq(Pf::Map[foo: "hello", bar: 200, baz: true, boo: 500])

      typeof(map).should eq(Pf::Map(String, String | Int32 | Bool))

      a = Pf::Map[foo: 100, bar: 200]
      b = Pf::Map(Int32 | String, Bool).new.assoc(0, true).assoc(1, false).assoc("foo", false)

      map = a.merge(b)
      map.should eq(
        Pf::Map(Int32 | String, Int32 | Bool).new
          .assoc("foo", false)
          .assoc("bar", 200)
          .assoc(0, true)
          .assoc(1, false)
      )
    end

    it "supports #merge(&)" do
      a = Pf::Map[foo: 100, bar: 200, baz: 300]
      b = Pf::Map[foo: 200, bar: 300.8, boo: 1000.5]

      map = a.merge(b) { |k, v1, v2| v1 + v2 }
      map.should eq(Pf::Map[foo: 300, bar: 500.8, baz: 300, boo: 1000.5])

      typeof(map).should eq(Pf::Map(String, Int32 | Float64))
    end

    it "supports #select(&)" do
      map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
      map.select { |_, v| v.even? }.should eq(Pf::Map[foo: 2, baz: 4])
      map.size.should eq(4)
    end

    it "supports #select(keys)" do
      map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
      map.select({"foo", "boo"}).should eq(Pf::Map[foo: 2, boo: 5])
      map.select("foo", "boo").should eq(Pf::Map[foo: 2, boo: 5])
    end

    it "supports #reject(&)" do
      map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
      map.reject { |_, v| v.even? }.should eq(Pf::Map[bar: 3, boo: 5])
      map.size.should eq(4)
    end

    it "supports #reject(keys)" do
      map = Pf::Map[foo: 2, bar: 3, baz: 4, boo: 5]
      map.reject({"foo", "boo"}).should eq(Pf::Map[bar: 3, baz: 4])
      map.reject("foo", "boo").should eq(Pf::Map[bar: 3, baz: 4])
    end

    it "supports #compact" do
      map = Pf::Map[foo: nil, bar: 123]
      map.compact.should eq(Pf::Map[bar: 123])

      typeof(map).should eq(Pf::Map(String, Int32?))
      typeof(map.compact).should eq(Pf::Map(String, Int32))
    end

    it "supports #fmap" do
      map = Pf::Map[foo: "John Doe", bar: "Samantha Doe"]
      map.fmap { |k, v| {k.upcase, v.upcase} }.should eq(Pf::Map["FOO": "JOHN DOE", "BAR": "SAMANTHA DOE"])
    end

    it "supports #map_key" do
      map = Pf::Map[foo: "John Doe", bar: "Samantha Doe"]
      map.map_key(&.upcase).should eq(Pf::Map["FOO": "John Doe", "BAR": "Samantha Doe"])
    end

    it "supports #map_value" do
      map = Pf::Map[foo: "John Doe", bar: "Samantha Doe"]
      map.map_value(&.upcase).should eq(Pf::Map[foo: "JOHN DOE", bar: "SAMANTHA DOE"])
    end

    it "supports #same?" do
      map1 = Pf::Map[foo: 123, bar: 456]
      map2 = map1.assoc("foo", 123)
      map1.same?(map2).should be_true
      map1.same?(map2.assoc("foo", 456)).should be_false
    end

    it "supports #clone" do
      map = Pf::Map[foo: [1, 2, 3], bar: [4, 5, 6]]
      map2 = map.clone

      map["foo"][0] = 100

      map.should eq(Pf::Map[foo: [100, 2, 3], bar: [4, 5, 6]])
      map2.should eq(Pf::Map[foo: [1, 2, 3], bar: [4, 5, 6]])
    end

    it "supports #hash" do
      map1 = Pf::Map[foo: 100, bar: 200]
      map2 = Pf::Map[foo: 100, bar: 200]
      map3 = Pf::Map[foo: "hello", bar: 200]
      map4 = Pf::Map[foo: 100, bar: 200, baz: 300]
      map5 = {"foo" => 100, "bar" => 200}
      map1.hash.should eq(map2.hash)
      map1.hash.should_not eq(map3.hash)
      map1.hash.should_not eq(map4.hash)
      map1.hash.should_not eq(map5.hash)
    end

    it "supports Enumerable#to_pf_map" do
      (0...5).zip('a'..'z').to_pf_map.should eq(
        Pf::Map
          .assoc(0, 'a')
          .assoc(1, 'b')
          .assoc(2, 'c')
          .assoc(3, 'd')
          .assoc(4, 'e')
      )

      ({'a', 'b', 'c', 'd'}).zip(0..3).to_pf_map.should eq(
        Pf::Map
          .assoc('a', 0)
          .assoc('b', 1)
          .assoc('c', 2)
          .assoc('d', 3)
      )
    end
  end

  it "should raise resolved error if commit is retained" do
    cobj = nil
    map = Pf::Map[name: "John", age: 23]
    map.transaction do |commit|
      cobj = commit
      commit.assoc("age", 25)
    end
    cobj.not_nil!["name"]?.should eq("John")
    cobj.not_nil!["age"]?.should eq(25)
    expect_raises(Pf::ResolvedError) { cobj.not_nil!.assoc("name", "Susan") }
    expect_raises(Pf::ResolvedError) { cobj.not_nil!.dissoc("name") }
    expect_raises(Pf::ResolvedError) { cobj.not_nil!.resolve }
  end

  it "should raise readonly error if commit is passed to another fiber" do
    went_through_chain = Channel(Bool).new
    chan_assoc = Channel(Pf::Map::Commit(String, Int32)).new
    chan_dissoc = Channel(Pf::Map::Commit(String, Int32)).new
    chan_resolve = Channel(Pf::Map::Commit(String, Int32)).new

    spawn do
      commit = chan_assoc.receive
      begin
        commit.assoc("foo", 123)
        went_through_chain.send(false)
      rescue Pf::ReadonlyError
        chan_dissoc.send(commit)
      end
    end

    spawn do
      commit = chan_dissoc.receive
      begin
        commit.dissoc("foo")
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

    map = Pf::Map[foo: 0, bar: 1, baz: 2]
    map.transaction do |commit|
      chan_assoc.send(commit)
      went_through_chain.receive.should be_true
    end
  end

  it "should pass the novels example" do
    n1 = File.read("#{__DIR__}/novels/01.txt")
    n2 = File.read("#{__DIR__}/novels/02.txt")
    n3 = File.read("#{__DIR__}/novels/03.txt")
    n4 = File.read("#{__DIR__}/novels/04.txt")

    # Get the tallies of all words in each novel and of all characters
    # in each novel.
    words_n1 = n1.split(/\s+/)
    words_n2 = n2.split(/\s+/)
    words_n3 = n3.split(/\s+/)
    words_n4 = n4.split(/\s+/)

    map_tally1 = words_n1.reduce(Pf::Map(String, Int32).new) { |map, word| map.assoc(word, (map[word]? || 0) + 1) }
    map_tally2 = words_n2.reduce(Pf::Map(String, Int32).new) { |map, word| map.assoc(word, (map[word]? || 0) + 1) }
    map_tally3 = Pf::Map(String, Int32).transaction do |commit|
      words_n3.each do |word|
        commit.assoc(word, (commit[word]? || 0) + 1)
      end
    end
    map_tally4 = Pf::Map(String, Int32).transaction do |commit|
      words_n4.each do |word|
        commit.assoc(word, (commit[word]? || 0) + 1)
      end
    end

    map_tally1.size.should eq(5308)
    map_tally1.sum { |_, n| n }.should eq(26471)

    map_tally2.size.should eq(25419)
    map_tally2.sum { |_, n| n }.should eq(230092)

    map_tally3.size.should eq(22858)
    map_tally3.sum { |_, n| n }.should eq(195855)

    map_tally4.size.should eq(13099)
    map_tally4.sum { |_, n| n }.should eq(56169)

    # Merge tallies into one big map (& hash for verifying).
    map_tally_total = map_tally1
      .merge(map_tally2) { |k, v1, v2| v1 + v2 }
      .merge(map_tally3) { |k, v1, v2| v1 + v2 }
      .merge(map_tally4) { |k, v1, v2| v1 + v2 }

    map_tally_total.size.should eq(45985)
    map_tally_total.sum { |_, n| n }.should eq(508587)

    # Find max used pair in total.
    max_used_map = map_tally_total.max_by { |_, n| n }
    max_used_map.should eq({"the", 26808})

    # Find which words in the first novel are not in the second novel.
    map_uwords12 = map_tally1.reject { |k, v| k.in?(map_tally2) }
    map_tally1.select { |k, v| !k.in?(map_tally2) }.should eq(map_uwords12)
    map_uwords12.size.should eq(2811)

    # Get the most used one
    word, count = map_uwords12.max_by { |_, n| n }
    word.should eq("Alice")
  end

  describe "Pf::Eq" do
    it "works with info example" do
      people = Pf::Map
        .assoc(0, Info1.new("John", "Doe"))
        .assoc(1, Info1.new("Barbara", "Doe"))

      people.assoc(0, Info1.new("John", "Doe")).should_not be(people)

      people = Pf::Map
        .assoc(0, Info2.new("John", "Doe"))
        .assoc(1, Info2.new("Barbara", "Doe"))

      people.assoc(0, Info2.new("John", "Doe")).should be(people)
    end
  end
end

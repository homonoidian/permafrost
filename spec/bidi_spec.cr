require "./spec_helper"

describe Pf::BidiMap do
  it "should create an empty map on .new" do
    bidi = Pf::BidiMap(String, Int32).new
    bidi.empty?.should be_true
  end

  it "should support creation from enumerable" do
    (0...3).zip('a'...'z').to_pf_bidi.should eq(
      Pf::BidiMap
        .assoc(0, 'a')
        .assoc(1, 'b')
        .assoc(2, 'c')
    )
  end

  it "should support #assoc and lookup using #key_for?, #value_for?" do
    bidi = Pf::BidiMap.assoc("John Doe", 100).assoc("Nancy Doe", 200)

    bidi.value_for?("John Doe").should eq(100)
    bidi.value_for?("Nancy Doe").should eq(200)
    bidi.value_for?("Bob Doe").should be_nil

    bidi.key_for?(100).should eq("John Doe")
    bidi.key_for?(200).should eq("Nancy Doe")
    bidi.key_for?(300).should be_nil

    newbidi = bidi.assoc("John Doe", 101)
    newbidi.value_for?("John Doe").should eq(101)
    newbidi.value_for?("Nancy Doe").should eq(200)
    newbidi.value_for?("Bob Doe").should be_nil

    newbidi.key_for?(100).should be_nil
    newbidi.key_for?(101).should eq("John Doe")
    newbidi.key_for?(200).should eq("Nancy Doe")
    newbidi.key_for?(300).should be_nil

    koverride = bidi.assoc("Barbara Doe", 200)
    koverride.value_for?("Nancy Doe").should be_nil
    koverride.value_for?("Barbara Doe").should eq(200)
    koverride.key_for?(200).should eq("Barbara Doe")

    expect_raises(KeyError, "Missing bidirectional map key for value: 100") do
      newbidi.key_for(100)
    end
    expect_raises(KeyError, "Missing bidirectional map key for value: 300") do
      newbidi.key_for(300)
    end
    expect_raises(KeyError, "Missing bidirectional map value for key: \"Nancy Doe\"") do
      koverride.value_for("Nancy Doe")
    end
  end

  it "should support #each" do
    bidi = Pf::BidiMap.assoc("John Doe", 100).assoc("Nancy Doe", 200)
    bidi.to_set.should eq(Set{ {"John Doe", 100}, {"Nancy Doe", 200} })
  end

  it "should support #has_key_for? and #has_value_for?" do
    bidi = Pf::BidiMap.assoc("John Doe", 100).assoc("Nancy Doe", 200)
    bidi.size.should eq(2)

    bidi.has_key_for?(100).should be_true
    bidi.has_key_for?(200).should be_true
    bidi.has_key_for?(300).should be_false
    bidi.has_key_for?(:boo).should be_false

    bidi.has_value_for?("John Doe").should be_true
    bidi.has_value_for?("Nancy Doe").should be_true
    bidi.has_value_for?("Barbara Doe").should be_false
    bidi.has_value_for?(:boo).should be_false
  end

  it "should support #dissoc_by_key and #dissoc_by_value" do
    bidi = Pf::BidiMap.assoc("John Doe", 100).assoc("Nancy Doe", 200)

    a = bidi.dissoc_by_key("John Doe")
    a.has_key_for?(100).should be_false
    a.has_key_for?(200).should be_true
    a.has_value_for?("John Doe").should be_false
    a.has_value_for?("Nancy Doe").should be_true

    a = bidi.dissoc_by_key("Nancy Doe")
    a.has_key_for?(100).should be_true
    a.has_key_for?(200).should be_false
    a.has_value_for?("John Doe").should be_true
    a.has_value_for?("Nancy Doe").should be_false

    b = bidi.dissoc_by_value(100)
    b.has_key_for?(100).should be_false
    b.has_key_for?(200).should be_true
    b.has_value_for?("John Doe").should be_false
    b.has_value_for?("Nancy Doe").should be_true

    b = bidi.dissoc_by_value(200)
    b.has_key_for?(100).should be_true
    b.has_key_for?(200).should be_false
    b.has_value_for?("John Doe").should be_true
    b.has_value_for?("Nancy Doe").should be_false
  end
end

require "./spec_helper"

describe Pf::UPath32 do
  it "supports #append, #prior, #goto, equality" do
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
    y = y.goto(56u32).prior.prior.goto(10u32)
    y.should eq(Pf::UPath32[100, 30, 20, 5, 5, 3, 8, 15, 4, 0, 0, 10])
  end

  it "supports #prepend" do
    Pf::UPath32[1, 2, 3].prepend(0).should eq(Pf::UPath32[0, 1, 2, 3])
  end
end

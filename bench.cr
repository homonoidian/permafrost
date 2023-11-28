require "benchmark"
require "./src/permafrost"

# This patch is necessary to get rid of Hasher's random seed. Otherwise
# benchmark results will depend on how good the seed (~> hash) is, meaning
# they will be random without this patch.

class Pf::Core::Node
  macro hash32(object)
    ({{object}}).hash(Crystal::Hasher.new(0u64, 0u64)).result.unsafe_as(UInt32)
  end
end

indices = (0...100_000).to_a.shuffle!

m0 = Pf::Map(Int32, Int32).new
indices.each do |n|
  m0 = m0.assoc(n, n)
end

a0 = {} of Int32 => Int32
indices.each do |n|
  a0[n] = n
end

Benchmark.ips do |x|
  x.report("add speed of light") do
    a = {} of Int32 => Int32
    indices.each do |n|
      a[n] = n
    end
  end

  x.report("add + delete speed of light") do
    a = {} of Int32 => Int32
    indices.each do |n|
      a[n] = n
    end
    indices.each do |n|
      a.delete(n)
    end
  end

  x.report("each speed of light") do
    a0.sum(0u128) { |_, n| n }
  end

  x.report("add") do
    m = Pf::Map(Int32, Int32).new
    indices.each do |n|
      m = m.assoc(n, n)
    end
  end

  x.report("add + delete") do
    m = Pf::Map(Int32, Int32).new
    indices.each do |n|
      m = m.assoc(n, n)
    end
    indices.each do |n|
      m = m.dissoc(n)
    end
  end

  x.report("each") do
    m0.sum(0u128) { |_, n| n }
  end

  x.report("ten assoc()s") do
    m = Pf::Map(Int32, Int32).new
    10.times do |n|
      m = m.assoc(n, n)
    end
  end
end

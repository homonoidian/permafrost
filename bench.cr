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

m0 = Pf::Map(Int32, Int32).new
100_000.times do |n|
  m0 = m0.assoc(n, n)
end

Benchmark.ips do |x|
  x.report("add") do
    m = Pf::Map(Int32, Int32).new
    100_000.times do |n|
      m = m.assoc(n, n)
    end
  end

  x.report("delete") do
    m = m0
    100_000.times do |n|
      m = m.dissoc(n)
    end
  end
end

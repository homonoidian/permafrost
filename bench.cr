require "benchmark"
require "./src/permafrost"
require "immutable"

indices = (0...100_000).to_a.shuffle!

m0 = Pf::Map(Int32, Int32).new
indices.each do |n|
  m0 = m0.assoc(n, n)
end

i0 = Immutable::Map(Int32, Int32).new
indices.each do |n|
  i0 = i0.set(n, n)
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

  x.report("pf::map add") do
    m = Pf::Map(Int32, Int32).new
    indices.each do |n|
      m = m.assoc(n, n)
    end
  end

  x.report("pf::map add + delete") do
    m = Pf::Map(Int32, Int32).new
    indices.each do |n|
      m = m.assoc(n, n)
    end
    indices.each do |n|
      m = m.dissoc(n)
    end
  end

  x.report("pf::map add tx") do
    m = Pf::Map(Int32, Int32).new
    m.transaction do |commit|
      indices.each do |n|
        commit.assoc(n, n)
      end
    end
  end

  x.report("pf::map add + delete tx") do
    m = Pf::Map(Int32, Int32).new
    m.transaction do |commit|
      indices.each do |n|
        commit.assoc(n, n)
      end
      indices.each do |n|
        commit.dissoc(n)
      end
    end
  end

  x.report("pf::map each") do
    m0.sum(0u128) { |_, n| n }
  end

  x.report("immutable::map add") do
    m = Immutable::Map(Int32, Int32).new
    indices.each do |n|
      m = m.set(n, n)
    end
  end

  x.report("immutable::map add + delete") do
    m = Immutable::Map(Int32, Int32).new
    indices.each do |n|
      m = m.set(n, n)
    end
    indices.each do |n|
      m = m.delete(n)
    end
  end

  x.report("immutable::map add transient") do
    m = Immutable::Map(Int32, Int32).new
    m.transient do |t|
      indices.each do |n|
        t.set(n, n)
      end
    end
  end

  x.report("immutable::map add + delete transient") do
    m = Immutable::Map(Int32, Int32).new
    m.transient do |t|
      indices.each do |n|
        t.set(n, n)
      end
      indices.each do |n|
        t.delete(n)
      end
    end
  end

  x.report("immutable::map each") do
    i0.sum(0u128) { |_, n| n }
  end
end

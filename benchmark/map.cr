require "benchmark"
require "../src/permafrost"
require "immutable"

# SYNTHETIC

indices = (0...100_000).to_a.shuffle!

m0 = Pf::Map(Int32, Int32).new
indices.each { |n| m0 = m0.assoc(n, n) }

i0 = Immutable::Map(Int32, Int32).new
indices.each { |n| i0 = i0.set(n, n) }

a0 = {} of Int32 => Int32
indices.each { |n| a0[n] = n }

Benchmark.ips do |x|
  x.report("Hash (speed of light): add") do
    a = {} of Int32 => Int32
    indices.each do |n|
      a[n] = n
    end
  end

  x.report("Pf::Map: add") do
    m = Pf::Map(Int32, Int32).new
    indices.each do |n|
      m = m.assoc(n, n)
    end
  end

  x.report("Immutable::Map: add") do
    m = Immutable::Map(Int32, Int32).new
    indices.each do |n|
      m = m.set(n, n)
    end
  end

  x.report("Pf::Map: add txn") do
    m = Pf::Map(Int32, Int32).new
    m.transaction do |commit|
      indices.each do |n|
        commit.assoc(n, n)
      end
    end
  end

  x.report("Immutable::Map: add txn") do
    m = Immutable::Map(Int32, Int32).new
    m.transient do |t|
      indices.each do |n|
        t.set(n, n)
      end
    end
  end
end

Benchmark.ips do |x|
  x.report("Hash (speed of light): add + delete") do
    a = {} of Int32 => Int32
    indices.each do |n|
      a[n] = n
    end
    indices.each do |n|
      a.delete(n)
    end
  end

  x.report("Pf::Map: add + delete") do
    m = Pf::Map(Int32, Int32).new
    indices.each do |n|
      m = m.assoc(n, n)
    end
    indices.each do |n|
      m = m.dissoc(n)
    end
  end

  x.report("Immutable::Map: add + delete") do
    m = Immutable::Map(Int32, Int32).new
    indices.each do |n|
      m = m.set(n, n)
    end
    indices.each do |n|
      m = m.delete(n)
    end
  end

  x.report("Pf::Map: add + delete txn") do
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

  x.report("Immutable::Map: add + delete txn") do
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
end

Benchmark.ips do |x|
  x.report("Hash (speed of light): each") do
    a0.sum(0u128) { |_, n| n }
  end

  x.report("Pf::Map: each") do
    m0.sum(0u128) { |_, n| n }
  end

  x.report("Immutable::Map: each") do
    i0.sum(0u128) { |_, n| n }
  end
end

# A TINY BIT MORE PRACTICAL

n1 = File.read("#{__DIR__}/../spec/novels/01.txt")
n1words = n1.split(/\s+/)
n2 = File.read("#{__DIR__}/../spec/novels/02.txt")
n2words = n2.split(/\s+/)
n3 = File.read("#{__DIR__}/../spec/novels/03.txt")
n3words = n3.split(/\s+/)
n4 = File.read("#{__DIR__}/../spec/novels/04.txt")
n4words = n4.split(/\s+/)

Benchmark.ips do |x|
  x.report("Hash (speed of light): word max") do
    table = {} of String => Int32
    {n1words, n2words, n3words, n4words}.each do |words|
      words.each { |word| table[word] = (table[word]? || 0) + 1 }
    end
    maxword, _ = table.max_by { |_, tally| tally }
    unless maxword == "the"
      raise "BUG"
    end
  end

  x.report("Pf::Map: word max imm") do
    table = Pf::Map(String, Int32).new
    {n1words, n2words, n3words, n4words}.each do |words|
      words.each { |word| table = table.assoc(word, (table[word]? || 0) + 1) }
    end
    maxword, _ = table.max_by { |_, tally| tally }
    unless maxword == "the"
      raise "BUG"
    end
  end

  x.report("Immutable::Map: word max imm") do
    table = Immutable::Map(String, Int32).new
    {n1words, n2words, n3words, n4words}.each do |words|
      words.each { |word| table = table.set(word, (table[word]? || 0) + 1) }
    end
    maxword, _ = table.max_by { |_, tally| tally }
    unless maxword == "the"
      raise "BUG"
    end
  end

  x.report("Pf::Map: word max txn") do
    table = Pf::Map(String, Int32).transaction do |commit|
      {n1words, n2words, n3words, n4words}.each do |words|
        words.each { |word| commit.assoc(word, (commit[word]? || 0) + 1) }
      end
    end
    maxword, _ = table.max_by { |_, tally| tally }
    unless maxword == "the"
      raise "BUG"
    end
  end
end

Benchmark.ips do |x|
  x.report("Hash (speed of light): bigram bag jaccard") do
    tables = {n1, n2, n3, n4}.map do |novel|
      table = {} of {Char, Char} => Int32

      r = Char::Reader.new(novel)
      loop do
        ch0 = r.current_char
        break if ch0 == '\0'
        r.next_char
        ch1 = r.current_char

        table[{ch0, ch1}] = (table[{ch0, ch1}]? || 0) + 1
      end

      table
    end

    # naive
    ix = {} of {Char, Char} => Int32
    tables.each do |a|
      a.each do |x, n|
        next if ix.has_key?(x)
        intersects = tables.all? do |b|
          a.same?(b) || ((m = b[x]?) && m >= n)
        end
        next unless intersects
        ix[x] = n
      end
    end

    u = {} of {Char, Char} => Int32
    tables.each do |a|
      a.each do |x, n|
        u[x] = (u[x]? || 0) + n
      end
    end

    jaccard = ix.sum { |_, n| n } / u.sum { |_, m| m }

    if (jaccard - 0.046).abs > 0.001
      raise "BUG"
    end
  end

  x.report("Pf::Map: bigram bag jaccard imm") do
    tables = {n1, n2, n3, n4}.map do |novel|
      table = Pf::Map({Char, Char}, Int32).new

      r = Char::Reader.new(novel)
      loop do
        ch0 = r.current_char
        break if ch0 == '\0'
        r.next_char
        ch1 = r.current_char

        table = table.assoc({ch0, ch1}, (table[{ch0, ch1}]? || 0) + 1)
      end

      table
    end

    # naive
    ix = Pf::Map({Char, Char}, Int32).new
    tables.each do |a|
      a.each do |x, n|
        next if ix.has_key?(x)
        intersects = tables.all? do |b|
          a.same?(b) || ((m = b[x]?) && m >= n)
        end
        next unless intersects
        ix = ix.assoc(x, n)
      end
    end

    u = Pf::Map({Char, Char}, Int32).new
    tables.each do |a|
      a.each do |x, n|
        u = u.assoc(x, (u[x]? || 0) + n)
      end
    end

    jaccard = ix.sum { |_, n| n } / u.sum { |_, m| m }

    if (jaccard - 0.046).abs > 0.001
      raise "BUG"
    end
  end

  x.report("Pf::Map: bigram bag jaccard txn") do
    tables = {n1, n2, n3, n4}.map do |novel|
      Pf::Map({Char, Char}, Int32).transaction do |commit|
        r = Char::Reader.new(novel)
        loop do
          ch0 = r.current_char
          break if ch0 == '\0'
          r.next_char
          ch1 = r.current_char

          commit.assoc({ch0, ch1}, (commit[{ch0, ch1}]? || 0) + 1)
        end
      end
    end

    # naive
    ix = Pf::Map({Char, Char}, Int32).transaction do |commit|
      tables.each do |a|
        a.each do |x, n|
          next if x.in?(commit)
          intersects = tables.all? do |b|
            a.same?(b) || ((m = b[x]?) && m >= n)
          end
          next unless intersects
          commit.assoc(x, n)
        end
      end
    end

    u = Pf::Map({Char, Char}, Int32).transaction do |commit|
      tables.each do |a|
        a.each do |x, n|
          commit.assoc(x, (commit[x]? || 0) + n)
        end
      end
    end

    jaccard = ix.sum { |_, n| n } / u.sum { |_, m| m }

    if (jaccard - 0.046).abs > 0.001
      raise "BUG"
    end
  end

  x.report("Immutable::Map: bigram bag jaccard imm") do
    tables = {n1, n2, n3, n4}.map do |novel|
      table = Immutable::Map({Char, Char}, Int32).new

      r = Char::Reader.new(novel)
      loop do
        ch0 = r.current_char
        break if ch0 == '\0'
        r.next_char
        ch1 = r.current_char

        table = table.set({ch0, ch1}, (table[{ch0, ch1}]? || 0) + 1)
      end

      table.as(Immutable::Map({Char, Char}, Int32)) # otherwise Crystal compiler crashes
    end

    # naive
    ix = Immutable::Map({Char, Char}, Int32).new
    tables.each do |a|
      a.each do |x, n|
        next if !!ix[x]?
        intersects = tables.all? do |b|
          a.same?(b) || ((m = b[x]?) && m >= n)
        end
        next unless intersects
        ix = ix.set(x, n)
      end
    end

    u = Immutable::Map({Char, Char}, Int32).new
    tables.each do |a|
      a.each do |x, n|
        u = u.set(x, (u[x]? || 0) + n)
      end
    end

    jaccard = ix.sum { |_, n| n } / u.sum { |_, m| m }

    if (jaccard - 0.046).abs > 0.001
      raise "BUG"
    end
  end
end

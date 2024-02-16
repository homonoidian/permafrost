module Enumerable(T)
  # Creates a `Pf::Map` out of `{key, value}` tuple pairs returned
  # by the block.
  #
  # ```
  # (0...10).to_pf_map { |n| {n, n * 2} } # => Pf::Map{2 => 4, 3 => 6, 4 => 8, ...}
  # ```
  def to_pf_map(& : T -> {K, V}) : Pf::Map(K, V) forall K, V
    Pf::Map(K, V).transaction do |commit|
      each { |el| commit.assoc(*yield el) }
    end
  end

  # Creates a `Pf::Map` out of an Enumerable whose elements respond
  # to `.[0]` and `.[1]`.
  #
  # ```
  # (0...10).zip('a'..'z').to_pf_map # => Pf::Map{0 => 'a', 1 => 'b', 2 => 'c', ...}
  # ```
  def to_pf_map
    Pf::Map.new(self)
  end

  # Creates a `Pf::Set` out of an Enumerable.
  #
  # ```
  # (0...5).to_pf_set # => Pf::Set[0, 1, 2, 3, 4]
  # ```
  def to_pf_set : Pf::Set(T)
    Pf::Set.new(self)
  end

  # Like `to_pf_map`, but creates a `Pf::BidiMap`.
  #
  # ```
  # (0...10).zip('a'...'z').to_pf_bidi # => Pf::BidiMap{0 <=> 'a', 1 <=> 'b', 2 <=> 'c', ...}
  # ```
  def to_pf_bidi
    Pf::BidiMap.new(self)
  end
end

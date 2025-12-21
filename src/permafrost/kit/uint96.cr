module Pf::Kit
  # :nodoc:
  #
  # NOTE: This struct is meant to be embedded within `UPath32`. Any other use is
  # discouraged. We embed it directly in `UPath32`, hence the use of `Packed`.
  @[Packed]
  struct UInt96
    MAX = (1u128 << 96) - 1

    # :nodoc:
    def initialize(@bits0 : UInt64, @bits1 : UInt32)
    end

    def self.zero : UInt96
      new(0u64, 0u32)
    end

    def self.new(data : UInt128)
      new(pack(data))
    end

    def self.new(bits : {UInt64, UInt32})
      new(bits[0], bits[1])
    end

    def self.pack(data : UInt128)
      if data > MAX
        raise OverflowError.new
      end

      {(data >> 32).to_u64, (data & UInt32::MAX).to_u32}
    end

    def self.unpack(bits0 : UInt64, bits1 : UInt32) : UInt128
      (bits0.to_u128 << 32) | bits1.to_u128
    end

    def to_u128 : UInt128
      UInt96.unpack(@bits0, @bits1)
    end

    def to_u32 : UInt32
      to_u128.to_u32
    end

    def &-(other : Int) : UInt96
      UInt96.new(to_u128 &- other)
    end

    def ~ : UInt96
      UInt96.new(~to_u128 & MAX)
    end

    def &(other : UInt96) : UInt96
      UInt96.new(to_u128 & other.to_u128)
    end

    def |(other : UInt96) : UInt96
      UInt96.new(to_u128 | other.to_u128)
    end

    def <<(other : UInt32) : UInt96
      UInt96.new(to_u128 << other)
    end

    def >>(other : UInt32) : UInt96
      UInt96.new(to_u128 >> other)
    end

    def inspect(io)
      to_u128.inspect(io)
    end
  end
end

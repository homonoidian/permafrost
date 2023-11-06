module Pf::Core
  struct Cloak(T)
    def initialize(@object : T)
    end

    def unwrap : T
      @object
    end
  end
end

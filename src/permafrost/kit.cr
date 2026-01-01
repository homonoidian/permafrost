module Pf::Kit
  # :nodoc:
  class AssertionError < Exception
  end

  # :nodoc:
  macro assert(x)
    raise ::Pf::Kit::AssertionError.new({{x.id.stringify}}) unless {{x}}
  end

  # Stack allocation using the experimental `ReferenceStorage` API.
  #
  # Reference: https://github.com/crystal-lang/crystal/issues/13481#issuecomment-2603298285
  #
  # See also in general: https://github.com/crystal-lang/crystal/issues/13481
  #
  # ```
  # class Foo
  #   def initialize(@a : UInt64, @b : UInt64)
  #   end
  # end
  #
  # foo = Pf::Kit.stack_alloc Foo.new(100u64, 200u64)
  # pp foo
  # ```
  macro stack_alloc(call)
    {% if call.is_a?(Assign) %}
      {% target = call.target %}
      {% call = call.value %}
      {{ target }} = uninitialized ReferenceStorage({{ call.receiver }})
      {{ call.receiver }}.unsafe_construct(pointerof({{ target }}), {% unless call.args.empty? %} {{ call.args.splat }}, {% end %}{% unless call.named_args.is_a?(Nop) %}{{ call.named_args.splat }}{% end %})
    {% else %}
      ::Pf::Kit.stack_alloc %storage = {{ call }}
    {% end %}
  end

  # Allocates a `HybridArray` whose main buffer is located on the stack and
  # has the given capacity *stackcap*.
  #
  # ```
  # ary = Pf::Kit.stack_array(Int32, 16)
  # ary << 100
  # ary << 200
  # ary << 300
  # pp ary # => HybridArray{100, 200, 300}
  # ```
  #
  # WARNING: the lifetime of the returned array is equal to the lifetime
  # of the function/method you call this in. Do not use this in e.g.
  # initialize: it's going to be the lifetime of the call to initialize,
  # *not* the instance's lifetime.
  macro stack_array(type, stackcap = 16)
    %buffer = uninitialized ({{type}})[{{stackcap}}]
    ::Pf::Kit.stack_alloc ::Pf::Kit::HybridArray({{type}}, {{stackcap}}).new(%buffer.to_unsafe)
  end
end

require "./kit/*"

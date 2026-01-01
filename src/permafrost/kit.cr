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
      {{@type}}.stack_alloc %storage = {{ call }}
    {% end %}
  end
end

require "./kit/*"

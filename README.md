# permafrost

Permafrost implements a (relatively) fast unordered persistent map. Plus a set
and a bidirectional map based on top of the map.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     permafrost:
       github: homonoidian/permafrost
   ```

2. Run `shards install`

## Usage

I implemented most useful stuff (?) from `Hash` and `Set`. `BidiMap` is mostly for myself
so you may forget it exists :) All in all refer to [the docs](https://homonoidian.github.io/permafrost/).

```crystal
require "permafrost"

map = Pf::Map[foo: 100, bar: 200]
map["foo"]? # => 100
map["bar"]? # => 200

map.assoc("baz", 300) # => Pf::Map{"foo" => 100, "bar" => 200, "baz" => 300}
map                   # => Pf::Map{"foo" => 100, "bar" => 200}

map.dissoc("foo) # => Pf::Map{"bar" => 200}
map              # => Pf::Map{"foo" => 100, "bar" => 200}
```

## Development

The implementation is pretty simple, it's found in `src/permafrost/core/node.cr`.
If you find any errors please let me know or (even better!) fix them yourself and
submit a PR. Same with new features.

## See also

I've no clue whether what I've written truly is a HAMT or not, as long
as it works I'm fine. Here are some "true" HAMTs:

- [Immutable](https://github.com/lucaong/immutable)
- [HAMT for C with good internals explanation](https://github.com/mkirchner/hamt)
- [Clojure's PersistentHashMap](https://github.com/clojure/clojure/blob/master/src/jvm/clojure/lang/PersistentHashMap.java)
- etc.

## Contributing

1. Fork it (<https://github.com/homonoidian/permafrost/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Alexey Yurchenko](https://github.com/homonoidian) - creator and maintainer

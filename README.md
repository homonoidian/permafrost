# permafrost

Permafrost implements a (relatively) fast unordered persistent map. Plus a set
and a bidirectional map based on the map.

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

map.dissoc("foo") # => Pf::Map{"bar" => 200}
map               # => Pf::Map{"foo" => 100, "bar" => 200}
```

## Performance

You can run the benchmark file, `bench.cr`, for a (very dumb and useless) benchmark
of the map vs. what we consider the speed-of-light implementation, `Hash`, and what
seems to be our only competitor, `Immutable::Map` from the wonderful shard [Immutable](https://github.com/lucaong/immutable).
The latter you'd have to install somehow, maybe by cloning this repo and modifying
`shard.yml` directly.

Note that each benchmark run you'd get (somewhat) different results depending on how
good the hash seed was, which is picked by Crystal randomly. I haven't found a way
to reliably disable that. If you know how let me know, maybe make a PR or something.

```text
                   add speed of light 228.59  (  4.37ms) (±14.11%)  4.75MB/op    26.60× slower
          add + delete speed of light 152.26  (  6.57ms) (±12.12%)  4.75MB/op    39.93× slower
                  each speed of light   6.08k (164.48µs) (± 0.18%)    0.0B/op          fastest
                          pf::map add   8.54  (117.13ms) (± 8.92%)    98MB/op   712.10× slower
                 pf::map add + delete   4.33  (231.07ms) (± 3.70%)   189MB/op  1404.84× slower
                       pf::map add tx  57.24  ( 17.47ms) (±18.02%)  7.78MB/op   106.22× slower
              pf::map add + delete tx  38.76  ( 25.80ms) (±20.76%)  7.78MB/op   156.84× slower
                         pf::map each 280.95  (  3.56ms) (± 0.70%)    0.0B/op    21.64× slower
                   immutable::map add   3.52  (284.13ms) (±10.84%)   219MB/op  1727.44× slower
          immutable::map add + delete   1.74  (574.02ms) (± 2.66%)   373MB/op  3489.90× slower
         immutable::map add transient   6.26  (159.64ms) (±11.90%)   101MB/op   970.58× slower
immutable::map add + delete transient   3.33  (300.57ms) (± 1.33%)   134MB/op  1827.38× slower
                  immutable::map each   6.40  (156.36ms) (± 2.67%)  87.4MB/op   950.61× slower
```

The ± numbers being so big smells weird, but the results clearly show the winner!

Again, I picked this run among others because it is the fastest. With a different hash seed,
you'll get different results, faster or slower than those presented here.

## Development

The implementation is pretty simple, it's found in `src/permafrost/core/node.cr`.
If you find any errors please let me know or (even better!) fix them yourself and
submit a PR. Same with new features. New methods for `Pf::Map`, `Pf::Set` and `Pf::BidiMap` are especially welcome.


## See also

I've no clue whether what I've written truly is a HAMT or not, as long
as it works I'm fine. For reference, here are some HAMTs that consider themselves HAMTs:

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

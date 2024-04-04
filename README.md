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
                   add speed of light 248.08  (  4.03ms) (±14.85%)  4.75MB/op    24.15× slower
          add + delete speed of light 185.80  (  5.38ms) (±14.95%)  4.75MB/op    32.24× slower
                  each speed of light   5.99k (166.94µs) (± 0.11%)    0.0B/op          fastest
                          pf::map add  10.06  ( 99.41ms) (±15.09%)   102MB/op   595.46× slower
                 pf::map add + delete   4.76  (209.87ms) (± 6.69%)   197MB/op  1257.12× slower
                       pf::map add tx  61.16  ( 16.35ms) (±19.17%)  7.11MB/op    97.94× slower
              pf::map add + delete tx  34.49  ( 28.99ms) (±15.60%)  7.11MB/op   173.66× slower
                         pf::map each 392.52  (  2.55ms) (± 6.44%)  2.17kB/op    15.26× slower
                   immutable::map add   3.27  (305.69ms) (± 9.73%)   219MB/op  1831.09× slower
          immutable::map add + delete   1.64  (611.49ms) (± 2.58%)   374MB/op  3662.89× slower
         immutable::map add transient   5.70  (175.40ms) (±10.56%)   101MB/op  1050.69× slower
immutable::map add + delete transient   3.29  (303.55ms) (± 1.99%)   134MB/op  1818.29× slower
                  immutable::map each   6.80  (147.04ms) (± 9.53%)  87.4MB/op   880.81× slower
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

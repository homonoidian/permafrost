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
                   add speed of light 246.08  (  4.06ms) (±10.20%)  4.75MB/op    3996.95× slower
          add + delete speed of light 180.79  (  5.53ms) (±13.95%)  4.75MB/op    5440.44× slower
                  each speed of light   5.99k (166.85µs) (± 0.06%)    0.0B/op     164.11× slower
                          pf::map add  11.27  ( 88.75ms) (±15.27%)  94.8MB/op   87291.70× slower
                 pf::map add + delete   5.45  (183.59ms) (± 7.59%)   185MB/op  180574.80× slower
                       pf::map add tx  81.73  ( 12.24ms) (±21.03%)  4.73MB/op   12034.54× slower
              pf::map add + delete tx  50.65  ( 19.74ms) (±16.36%)  4.73MB/op   19418.83× slower
                         pf::map each 666.27  (  1.50ms) (± 1.96%)  2.27kB/op    1476.23× slower
                   immutable::map add   3.42  (292.54ms) (±12.00%)   219MB/op  287731.67× slower
          immutable::map add + delete   1.68  (595.51ms) (± 2.07%)   373MB/op  585727.94× slower
         immutable::map add transient   6.06  (165.15ms) (±11.56%)   101MB/op  162433.23× slower
immutable::map add + delete transient   3.28  (304.88ms) (± 2.18%)   134MB/op  299866.65× slower
                  immutable::map each   7.05  (141.87ms) (± 9.33%)  87.4MB/op  139537.29× slower
```

The ± numbers being so big smells weird, but the results clearly show the winner! Note how
memory use is almost the same between `Pf::Map` with transactions and `Hash`.

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

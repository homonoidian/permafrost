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
                   add speed of light 237.89  (  4.20ms) (±12.31%)  4.75MB/op    24.99× slower
          add + delete speed of light 177.93  (  5.62ms) (±13.60%)  4.75MB/op    33.41× slower
                  each speed of light   5.94k (168.23µs) (± 1.35%)    0.0B/op          fastest
                          pf::map add   8.45  (118.37ms) (±10.16%)   102MB/op   703.59× slower
                 pf::map add + delete   4.12  (242.62ms) (± 6.37%)   197MB/op  1442.18× slower
                       pf::map add tx  58.49  ( 17.10ms) (±18.50%)  7.13MB/op   101.62× slower
              pf::map add + delete tx  38.15  ( 26.21ms) (±19.07%)  7.13MB/op   155.80× slower
                         pf::map each 395.54  (  2.53ms) (± 2.48%)  2.17kB/op    15.03× slower
                   immutable::map add   3.26  (306.59ms) (± 8.76%)   219MB/op  1822.40× slower
          immutable::map add + delete   1.62  (615.78ms) (± 1.01%)   374MB/op  3660.31× slower
         immutable::map add transient   5.70  (175.44ms) (± 8.66%)   101MB/op  1042.87× slower
immutable::map add + delete transient   3.08  (324.19ms) (± 2.00%)   133MB/op  1927.06× slower
                  immutable::map each   6.06  (165.10ms) (± 5.81%)  87.3MB/op   981.39× slower
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

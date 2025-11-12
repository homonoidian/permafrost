# permafrost

Permafrost is a collection of thread-safe, persistent, immutable data structures for Crystal.

- An unordered map `Pf::Map`.
- An unordered set `Pf::Set`.
- An unordered bidirectional map (bimap) `Pf::BidiMap`.
- An unsigned 32-bit integer set `Pf::USet32`.

Most of the data structures in Permafrost come from my main project, [Wirewright](https://github.com/wirewright/wirewright).
Wirewright is also the main user of Permafrost.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     permafrost:
       github: homonoidian/permafrost
   ```

2. Run `shards install`

## Usage

See [the docs](https://homonoidian.github.io/permafrost/). 

> [!NOTE]
> Some safety checks are disabled in release mode. You can compile with `-Dsafe`
> to enable them in release mode.

## Performance

Benchmarks in `benchmark/` require Immutable for comparison. Run `shards install` while
in `benchmarks/` to install it.

My CPU: Ryzen 3 2200G.

> [!NOTE]
> You are recommended to compile the benchmarks with `--mcpu=native` to make sure the Crystal
> compiler and LLVM consider vectorization if your CPU supports it (this also enables optimizations
> specific to your CPU). I'm saying this because the benchmarks perform slightly worse without this
> flag on my machine.
>
> Since Permafrost is GC-heavy you are recommended to use `-Dpreview_mt`. An extremely efficient
> immutable map, the best one you can imagine, is basically a hair-thin wrapper around malloc.
> The GC/allocator you use plays a very important role here, and whether it runs on multiple threads etc.

### Map

See `benchmark/map.cr` for `Pf::Map` benchmark source code.

```text
$ crystal build map.cr -Dpreview_mt --release --mcpu native
```

```text
Hash (speed of light): add 275.57  (  3.63ms) (±16.29%)  4.75MB/op        fastest
          Pf::Map: add txn  49.50  ( 20.20ms) (±14.59%)  7.79MB/op   5.57× slower
              Pf::Map: add   8.38  (119.32ms) (± 9.15%)    98MB/op  32.88× slower
   Immutable::Map: add txn   5.82  (171.76ms) (±10.19%)   101MB/op  47.33× slower
       Immutable::Map: add   3.39  (295.09ms) (±11.34%)   219MB/op  81.32× slower

Hash (speed of light): add + delete 156.36  (  6.40ms) (±13.24%)  4.75MB/op        fastest
          Pf::Map: add + delete txn  32.74  ( 30.54ms) (±15.19%)  7.79MB/op   4.78× slower
              Pf::Map: add + delete   4.20  (238.05ms) (± 5.24%)   189MB/op  37.22× slower
   Immutable::Map: add + delete txn   3.07  (325.23ms) (± 1.59%)   133MB/op  50.85× slower
       Immutable::Map: add + delete   1.64  (608.61ms) (± 0.84%)   373MB/op  95.16× slower

Hash (speed of light): each   9.38k (106.61µs) (± 0.93%)    0.0B/op          fastest
              Pf::Map: each 271.59  (  3.68ms) (± 1.33%)    0.0B/op    34.54× slower
       Immutable::Map: each   6.16  (162.22ms) (± 4.29%)  87.4MB/op  1521.65× slower

Hash (speed of light): word max  28.73  ( 34.80ms) (± 8.71%)  3.75MB/op        fastest
          Pf::Map: word max txn   9.87  (101.29ms) (±16.64%)  25.7MB/op   2.91× slower
          Pf::Map: word max imm   1.94  (515.01ms) (± 2.38%)   395MB/op  14.80× slower
   Immutable::Map: word max imm 713.24m (  1.40s ) (± 1.57%)   870MB/op  40.28× slower

Hash (speed of light): bigram bag jaccard  15.11  ( 66.18ms) (± 1.97%)   522kB/op        fastest
          Pf::Map: bigram bag jaccard txn   4.68  (213.87ms) (± 6.50%)  87.5MB/op   3.23× slower
          Pf::Map: bigram bag jaccard imm 529.40m (  1.89s ) (± 0.72%)   1.7GB/op  28.54× slower
   Immutable::Map: bigram bag jaccard imm 188.77m (  5.30s ) (± 0.00%)  3.83GB/op  80.04× slower
```

### USet32

See `benchmark/uset32.cr` for `Pf::USet32` benchmark source code.

```text
$ crystal build uset32.cr -Dpreview_mt --release --mcpu native
```

```text
xs.size = 100k
ys.size = 20.0k
zs.size = 70.0k
ps.size = 60.0k

   Set: create 100k 498.90  (  2.00ms) (± 1.24%)  2.0MB/op        fastest
USet32: create 100k 366.27  (  2.73ms) (± 0.44%)  231kB/op   1.36× slower

USet32: subset ys xs   1.98M (504.31ns) (± 2.09%)  32.0B/op         fastest
   Set: subset ys xs   2.71k (369.01µs) (± 0.39%)   0.0B/op  731.72× slower

USet32: xs union zs   1.22M (818.00ns) (± 3.89%)  0.99kB/op          fastest
   Set: xs union zs 188.43  (  5.31ms) (± 1.55%)   6.0MB/op  6487.92× slower

USet32: union subset xs ys   1.97M (506.75ns) (± 1.87%)  32.0B/op          fastest
   Set: union subset xs ys 413.52  (  2.42ms) (± 1.84%)  2.0MB/op  4772.15× slower

   Set: xs intersects? zs (true)  89.44M ( 11.18ns) (± 1.49%)  0.0B/op        fastest
USet32: xs intersects? zs (true)  85.52M ( 11.69ns) (± 1.77%)  0.0B/op   1.05× slower

USet32: xs intersects? ps (false) 103.59M (  9.65ns) (± 1.40%)  0.0B/op            fastest
   Set: xs intersects? ps (false) 886.85  (  1.13ms) (± 0.62%)  0.0B/op  116802.34× slower

USet32: xs intersect zs 689.10k (  1.45µs) (± 2.87%)  2.79kB/op          fastest
   Set: xs intersect zs 360.09  (  2.78ms) (± 0.85%)   769kB/op  1913.68× slower

USet32: xs difference zs   1.27M (785.97ns) (± 3.57%)    608B/op          fastest
   Set: xs difference zs 156.01  (  6.41ms) (± 2.77%)  3.75MB/op  8155.08× slower

USet32: Jaccard xs zs 421.19k (  2.37µs) (± 2.16%)  3.78kB/op          fastest
   Set: Jaccard xs zs 106.82  (  9.36ms) (± 1.87%)  6.75MB/op  3943.10× slower
```

See also the docs for `Pf::USet32` for related prose.

> [!TODO]
> Compare with BitArray and CRoaring. We will likely win over BitArray due to copying
> overhead but lose to CRoaring due to indirection, although probably only on large
> bitmaps (whatever that means).

## Development

- If you find any errors please let me know or (even better!) fix them yourself and
  submit a PR.
- New methods or quality improvements are welcome, especially if they already exist in
  Crystal's stdlib.
- Optimizations are *especially* welcome. E.g. Wirewright currently uses Permafrost in
  extremely hot places. A dozen nanoseconds shaved off of something hot in Permafrost itself
  would be very nice.

## References

- Michael J. Steindorfer, Jurgen J. Vinju, [Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM Collections](https://michael.steindorfer.name/publications/oopsla15.pdf)
- Phil Bagwell, [Ideal Hash Trees](https://lampwww.epfl.ch/papers/idealhashtrees.pdf)
- [Immutable](https://github.com/lucaong/immutable)
- [HAMT for C with good internals explanation](https://github.com/mkirchner/hamt)
- [Clojure's PersistentHashMap](https://github.com/clojure/clojure/blob/master/src/jvm/clojure/lang/PersistentHashMap.java)
- [Roaring bitmaps](https://roaringbitmap.org/)

## Contributing

1. Fork it (<https://github.com/homonoidian/permafrost/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Alexey Yurchenko](https://github.com/homonoidian) - creator and maintainer

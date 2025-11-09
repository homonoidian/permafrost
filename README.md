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

## Performance

Benchmarks in `benchmark/` require Immutable for comparison. Run `shards install` while
in `benchmarks/` to install it.

My CPU: Ryzen 3 2200G.

> [!NOTE]
> You are recommended to compile the benchmarks with `--mcpu=native` to make sure the Crystal
> compiler and LLVM consider vectorization if your CPU supports it (this also enables optimizations
> specific to your CPU). I'm saying this because the benchmarks perform slightly worse without this
> flag on my machine.

### Map

See `benchmark/map.cr` for `Pf::Map` benchmark source code.

```text
$ crystal build map.cr --release --mcpu native
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
$ crystal build uset32.cr --release --mcpu native
```

```text
   Set: create 100k 527.73  (  1.89ms) (± 1.32%)  2.0MB/op        fastest
USet32: create 100k 339.35  (  2.95ms) (± 0.38%)  231kB/op   1.56× slower

USet32: subset   1.73M (578.78ns) (± 0.53%)  32.0B/op         fastest
   Set: subset   2.55k (391.65µs) (± 1.92%)   0.0B/op  676.67× slower

USet32: xs union zs   1.19M (839.41ns) (± 2.58%)  0.99kB/op          fastest
   Set: xs union zs 188.40  (  5.31ms) (± 5.98%)   6.0MB/op  6323.44× slower

USet32: union subset   1.69M (591.87ns) (± 0.57%)  32.0B/op          fastest
   Set: union subset 415.48  (  2.41ms) (± 1.25%)  2.0MB/op  4066.49× slower

USet32: xs intersects? zs  68.20M ( 14.66ns) (± 1.48%)  0.0B/op        fastest
   Set: xs intersects? zs  22.86M ( 43.74ns) (± 0.72%)  0.0B/op   2.98× slower

USet32: xs intersect zs 728.70k (  1.37µs) (± 2.05%)  2.79kB/op          fastest
   Set: xs intersect zs 355.38  (  2.81ms) (± 7.41%)   769kB/op  2050.48× slower

USet32: xs difference zs   1.26M (791.22ns) (± 2.34%)    608B/op          fastest
   Set: xs difference zs 163.83  (  6.10ms) (± 2.93%)  3.75MB/op  7714.66× slower

USet32: Jaccard 460.47k (  2.17µs) (± 0.87%)  3.78kB/op          fastest
   Set: Jaccard 114.97  (  8.70ms) (± 2.86%)  6.75MB/op  4005.12× slower
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

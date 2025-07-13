# later – Unicode collation in Zig

This is a Zig implementation of the
[Unicode Collation Algorithm](https://www.unicode.org/reports/tr10/), using no
dependencies beyond the standard library. `later` passes the conformance tests
for both the Default Unicode Collation Element Table (DUCET) and the root
collation order of the Common Locale Data Repository (CLDR). You can verify this
by running the tests:

```sh
zig build test --release=safe
```

## Usage example

```zig
const std = @import("std");
const later = @import("later");

test "sort multilingual list of names" {
    const alloc = std.testing.allocator;

    var coll = try later.Collator.initDefault(alloc);
    defer coll.deinit();

    var input = [_][]const u8{
        "چنگیز",
        "Éloi",
        "Ötzi",
        "Melissa",
        "صدام",
        "Mélissa",
        "Overton",
        "Elrond",
    };

    const expected = [_][]const u8{
        "Éloi",
        "Elrond",
        "Melissa",
        "Mélissa",
        "Ötzi",
        "Overton",
        "چنگیز",
        "صدام",
    };

    std.mem.sort([]const u8, &input, &coll, later.collateComparator);
    try std.testing.expectEqualSlices([]const u8, &expected, &input);
}
```

## Further notes

`later` is based on my somewhat more mature UCA implementation in Rust,
[feruca](https://github.com/theodore-s-beers/feruca). I wanted to learn Zig
properly, and Unicode collation is a good, non-trivial problem to solve toward
that end. Perhaps this collator will also be of use to others in the Zig
community.

It's worth noting that a substantial part of the work of implementing the UCA is
generating maps from Unicode data files. We need to be able to determine
quickly, for a given code point, its canonical decomposition, combining class,
collation weights, and more. I built the maps for `later` in a separate
repository, [uca-maps-zig](https://github.com/theodore-s-beers/uca-maps-zig).
They're serialized in simple custom binary formats (see `src/bin`) and loaded
on-demand in collation.

Another part of the fun in this project was implementing UTF-8
decoding/validation and Unicode form NFD normalization. It turns out the
algorithms are well established, and they work nicely, and they aren't all that
difficult to code. We stand on the shoulders of giants!

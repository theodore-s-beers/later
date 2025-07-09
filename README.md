# later – Unicode collation in Zig

This is still alpha software, but the conformance tests pass!

```sh
zig build test --release=safe
```

## Usage example

```zig
fn collateComparator(context: *Collator, a: []const u8, b: []const u8) bool {
    return context.collate(a, b) == .lt;
}

test "sort multilingual list of names" {
    const alloc = std.testing.allocator;

    var coll = try Collator.initDefault(alloc);
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

    std.mem.sort([]const u8, &input, &coll, collateComparator);
    try std.testing.expectEqualSlices([]const u8, &expected, &input);
}
```

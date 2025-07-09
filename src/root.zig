const std = @import("std");
const AutoHashMap = std.AutoHashMap;

const Collator = @import("collator").Collator;

test "Alice and Bob" {
    const alloc = std.testing.allocator;

    var coll = try Collator.initDefault(alloc);
    defer coll.deinit();

    const a = "Alice";
    const b = "Bob";

    try std.testing.expect(coll.collate(a, b) == .lt);
}

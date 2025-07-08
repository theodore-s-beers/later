const std = @import("std");
const AutoHashMap = std.AutoHashMap;

const Collator = @import("collator").Collator;

test "Alice and Bob" {
    const allocator = std.testing.allocator;

    var collator = try Collator.initDefault(allocator);
    defer collator.deinit();

    const a = "Alice";
    const b = "Bob";

    try std.testing.expect(collator.collate(a, b) == .lt);
}

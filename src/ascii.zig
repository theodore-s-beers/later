const std = @import("std");
const decode = @import("decode");
const util = @import("util");

// A decisive ASCII difference leaves partially filled buffers. Otherwise, finish
// decoding both inputs so the caller can continue with normalization and collation.
pub fn fillCodepointsAndCompareAscii(
    alloc: std.mem.Allocator,
    a_chars: *std.ArrayList(u32),
    b_chars: *std.ArrayList(u32),
    a: []const u8,
    b: []const u8,
) !?std.math.Order {
    a_chars.clearRetainingCapacity();
    b_chars.clearRetainingCapacity();
    var a_iter = decode.CodepointIterator{ .input = a };
    var b_iter = decode.CodepointIterator{ .input = b };
    var backup: ?std.math.Order = null;
    var ascii_failed = false;

    while (a_iter.next()) |a_char| {
        try a_chars.append(alloc, a_char);
        if (!asciiAlphanumeric(a_char)) {
            ascii_failed = true;
            break;
        }

        const b_char = b_iter.next() orelse break;
        try b_chars.append(alloc, b_char);
        if (!asciiAlphanumeric(b_char)) {
            ascii_failed = true;
            break;
        }

        if (a_char == b_char) continue;

        const a_folded = if (a_char > 0x5A) a_char - 0x20 else a_char;
        const b_folded = if (b_char > 0x5A) b_char - 0x20 else b_char;

        if (a_folded == b_folded) {
            if (backup == null) backup = util.cmp(u32, b_char, a_char);
            continue;
        }

        return util.cmp(u32, a_folded, b_folded);
    }

    try a_iter.appendRemaining(alloc, a_chars);
    try b_iter.appendRemaining(alloc, b_chars);

    if (ascii_failed) return null;
    if (a_chars.items.len != b_chars.items.len)
        return util.cmp(usize, a_chars.items.len, b_chars.items.len);
    return backup;
}

// ASCII range, not punctuation or symbols
fn asciiAlphanumeric(c: u32) bool {
    return (0x30 <= c and c <= 0x7A) and
        !(0x3A <= c and c <= 0x40) and
        !(0x5B <= c and c <= 0x60);
}

test "ASCII primary difference stops decoding and overrides case" {
    const alloc = std.testing.allocator;
    var a = std.ArrayList(u32).empty;
    defer a.deinit(alloc);
    var b = std.ArrayList(u32).empty;
    defer b.deinit(alloc);

    const order = try fillCodepointsAndCompareAscii(alloc, &a, &b, "aZ\xfftail", "Ab\xc2tail");
    try std.testing.expectEqual(std.math.Order.gt, order.?);
    try std.testing.expectEqualSlices(u32, &.{ 'a', 'Z' }, a.items);
    try std.testing.expectEqualSlices(u32, &.{ 'A', 'b' }, b.items);
}

test "ASCII case differences and prefixes" {
    const alloc = std.testing.allocator;
    var a = std.ArrayList(u32).empty;
    defer a.deinit(alloc);
    var b = std.ArrayList(u32).empty;
    defer b.deinit(alloc);

    const cases = .{
        .{ "aB", "Ab", std.math.Order.lt },
        .{ "AB", "ab", std.math.Order.gt },
        .{ "a", "AA", std.math.Order.lt },
        .{ "ab", "a", std.math.Order.gt },
        .{ "", "a", std.math.Order.lt },
        .{ "a", "", std.math.Order.gt },
        .{ "0", "A", std.math.Order.lt },
    };
    inline for (cases) |case| {
        const order = try fillCodepointsAndCompareAscii(alloc, &a, &b, case[0], case[1]);
        try std.testing.expectEqual(case[2], order.?);
    }
    try std.testing.expectEqual(null, try fillCodepointsAndCompareAscii(alloc, &a, &b, "same", "same"));
    try std.testing.expectEqual(null, try fillCodepointsAndCompareAscii(alloc, &a, &b, "", ""));
}

test "fallback completes both buffers and preserves malformed UTF-8" {
    const alloc = std.testing.allocator;
    var a = std.ArrayList(u32).empty;
    defer a.deinit(alloc);
    var b = std.ArrayList(u32).empty;
    defer b.deinit(alloc);

    // A prior case difference cannot decide the result once ASCII comparison fails.
    const left = "a-\xc2Xé\xf0\x9f\x98\x80";
    const right = "Aé\xe1\x80";
    const left_cps: []const u32 = &.{ 'a', '-', 0xFFFD, 'X', 0xE9, 0x1F600 };
    const right_cps: []const u32 = &.{ 'A', 0xE9, 0xFFFD };
    try std.testing.expectEqual(null, try fillCodepointsAndCompareAscii(alloc, &a, &b, left, right));
    try std.testing.expectEqualSlices(u32, left_cps, a.items);
    try std.testing.expectEqualSlices(u32, right_cps, b.items);

    // Exercise fallback from the other side, reusing the previous buffers.
    try std.testing.expectEqual(null, try fillCodepointsAndCompareAscii(alloc, &a, &b, "AXtail", "a\xc2Y"));
    try std.testing.expectEqualSlices(u32, &.{ 'A', 'X', 't', 'a', 'i', 'l' }, a.items);
    try std.testing.expectEqualSlices(u32, &.{ 'a', 0xFFFD, 'Y' }, b.items);
}

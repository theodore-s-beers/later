const std = @import("std");
const ccc = @import("ccc");
const Collator = @import("collator").Collator;

// Only inspect the boundary of a shared byte prefix. If it could participate in
// normalization, a contraction, or shifted weighting, keep the full input.
pub fn findByteOffset(coll: *Collator, a: []const u8, b: []const u8) usize {
    var end: usize = 0;
    while (end < @min(a.len, b.len) and a[end] == b[end]) : (end += 1) {}
    while (end > 0 and end < @min(a.len, b.len) and isContinuation(a[end])) end -= 1;
    if (end == 0) return 0;

    const previous = previousScalar(a, end) orelse return 0;
    const table = &coll.collation.?;
    if (table.maxLen(table.entry(previous.cp)) > 1) return 0;
    if (previous.start > 0) {
        const penultimate = previousScalar(a, previous.start) orelse return 0;
        if (table.maxLen(table.entry(penultimate.cp)) > 2) return 0;
    }
    if (coll.shifting and coll.getVariable(previous.cp)) return 0;

    const a_next = nextScalar(a, end) catch return 0;
    const b_next = nextScalar(b, end) catch return 0;
    if (a_next) |cp| if (leadingClass(coll, cp) != 0) return 0;
    if (b_next) |cp| if (leadingClass(coll, cp) != 0) return 0;
    return end;
}

fn leadingClass(coll: *Collator, cp: u32) u8 {
    if (cp < 0xC0) return 0;
    // A character with CCC zero can still decompose to leading combining marks.
    if (coll.getFCD(cp)) |fcd| return @intCast(fcd >> 8);
    return ccc.getCombiningClass(cp);
}

fn isContinuation(byte: u8) bool {
    return byte & 0xC0 == 0x80;
}

fn previousScalar(bytes: []const u8, end: usize) ?struct { cp: u32, start: usize } {
    var start = end - 1;
    while (start > 0 and isContinuation(bytes[start])) start -= 1;
    const len = std.unicode.utf8ByteSequenceLength(bytes[start]) catch return null;
    if (end - start != len) return null;
    const cp = std.unicode.utf8Decode(bytes[start..end]) catch return null;
    return .{ .cp = cp, .start = start };
}

fn nextScalar(bytes: []const u8, start: usize) !?u32 {
    if (start == bytes.len) return null;
    const len = try std.unicode.utf8ByteSequenceLength(bytes[start]);
    if (len > bytes.len - start) return error.TruncatedUtf8;
    return try std.unicode.utf8Decode(bytes[start..][0..len]);
}

pub fn findOffset(coll: *Collator) usize {
    const a = coll.a_chars.items;
    const b = coll.b_chars.items;
    var offset: usize = 0;

    while (offset < @min(a.len, b.len)) : (offset += 1) {
        if (a[offset] != b[offset]) break;
        if (coll.collation.?.maxLen(coll.collation.?.entry(a[offset])) > 1) break;
    }

    if (offset == 0) return 0;

    if (coll.shifting and coll.getVariable(a[offset - 1])) {
        if (offset > 1) {
            if (coll.getVariable(a[offset - 2])) return 0;
            return offset - 1;
        }

        return 0;
    }

    return offset;
}

test "byte prefix ends at complete scalars and preserves collation context" {
    var coll = try Collator.initDefault(std.testing.allocator);
    defer coll.deinit();
    const cases = .{
        .{ "shared漢x", "shared漢y", "shared漢".len },
        .{ "sharedéx", "sharedéy", 0 }, // Its expansion includes a primary-ignorable CE.
        .{ "xé", "xê", 1 }, // Shared UTF-8 starter is not a complete scalar.
        .{ "plain", "other", 0 },
        .{ "", "other", 0 },
        .{ "abc", "abcd", 3 },
        .{ "l·x", "l.x", 0 }, // L can start a contraction.
        .{ "\u{FB2}\u{F71}\u{F80}", "\u{FB2}\u{F71}x", 0 }, // Three-scalar contraction.
        .{ "e\u{301}", "ex", 0 }, // Combining mark crosses the boundary.
        .{ "a\u{F73}", "ax", 0 }, // CCC zero, but decomposition starts with a mark.
        .{ "x-abc", "x-def", 0 }, // Shifted state carries across punctuation.
        .{ "x\u{334}a", "x\u{334}b", 0 }, // Primary-ignorable boundary.
        .{ "a\xc2X", "a\xc2Y", 0 }, // Shared incomplete UTF-8 sequence.
        .{ "a\xffx", "a\xffy", 0 },
        .{ "abc", "abc\x80", 0 },
        .{ "a\xf0\x9f", "ax", 0 },
    };
    inline for (cases) |case| {
        try std.testing.expectEqual(@as(usize, case[2]), findByteOffset(&coll, case[0], case[1]));
        try std.testing.expectEqual(@as(usize, case[2]), findByteOffset(&coll, case[1], case[0]));
    }
    coll.shifting = false;
    try std.testing.expectEqual("sharedé".len, findByteOffset(&coll, "sharedéx", "sharedéy"));
    try std.testing.expectEqual(2, findByteOffset(&coll, "x-abc", "x-def"));
}

const std = @import("std");

pub const Collator = @import("collator").Collator;

pub fn collateComparator(context: *Collator, a: []const u8, b: []const u8) bool {
    return context.collate(a, b) == .lt;
}

fn conformance(alloc: std.mem.Allocator, path: []const u8, coll: *Collator) !void {
    const start_time = std.time.microTimestamp();
    defer {
        const end_time = std.time.microTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000.0;
        std.debug.print("{s}: {d:.2}ms\n", .{ path, duration_ms });
    }

    const test_data = try std.fs.cwd().readFileAlloc(alloc, path, 4 * 1024 * 1024);
    defer alloc.free(test_data);

    var max_line = std.ArrayList(u8).init(alloc);
    defer max_line.deinit();

    var test_string = std.ArrayList(u8).init(alloc);
    defer test_string.deinit();

    var line_iter = std.mem.splitScalar(u8, test_data, '\n');
    var i: usize = 0;

    outer: while (line_iter.next()) |line| {
        i += 1;
        if (line.len == 0 or line[0] == '#') continue;

        test_string.clearRetainingCapacity();

        var word_iter = std.mem.splitScalar(u8, line, ' ');
        while (word_iter.next()) |hex| {
            const val = try std.fmt.parseInt(u32, hex, 16);
            if (0xD800 <= val and val <= 0xDFFF) continue :outer; // Surrogate code points

            var utf8_bytes: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(@intCast(val), &utf8_bytes);
            try test_string.appendSlice(utf8_bytes[0..len]);
        }

        const comparison = coll.collate(test_string.items, max_line.items);
        if (comparison == .lt) std.debug.panic("Invalid collation order at line {}\n", .{i});

        std.mem.swap(std.ArrayList(u8), &max_line, &test_string);
    }
}

test "cldr non-ignorable" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .cldr, false, false);
    defer coll.deinit();

    try conformance(alloc, "test-data/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt", &coll);
}

test "cldr shifted" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .cldr, true, false);
    defer coll.deinit();

    try conformance(alloc, "test-data/CollationTest_CLDR_SHIFTED_SHORT.txt", &coll);
}

test "ducet non-ignorable" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .ducet, false, false);
    defer coll.deinit();

    try conformance(alloc, "test-data/CollationTest_NON_IGNORABLE_SHORT.txt", &coll);
}

test "ducet shifted" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .ducet, true, false);
    defer coll.deinit();

    try conformance(alloc, "test-data/CollationTest_SHIFTED_SHORT.txt", &coll);
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

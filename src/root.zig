const std = @import("std");

//
// Exports
//

pub const Collator = @import("collator").Collator;

pub fn collateComparator(context: *Collator, a: []const u8, b: []const u8) bool {
    return context.collate(a, b) == .lt;
}

//
// Conformance test function and helper
//

fn conformance(alloc: std.mem.Allocator, path: []const u8, coll: *Collator) void {
    const start_time = std.time.microTimestamp();
    defer {
        const end_time = std.time.microTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000.0;
        std.debug.print("{s}: {d:.2}ms\n", .{ path, duration_ms });
    }

    const test_data = std.fs.cwd().readFileAlloc(alloc, path, 4 * 1024 * 1024) catch unreachable;
    defer alloc.free(test_data);

    // Stack alloc for test strings
    var buf: [64]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const stack_alloc = fba.allocator();

    var max_line = std.ArrayList(u8).initCapacity(stack_alloc, 32) catch unreachable;
    var test_string = std.ArrayList(u8).initCapacity(stack_alloc, 32) catch unreachable;

    var line_iter = std.mem.splitScalar(u8, test_data, '\n');
    var i: usize = 0;

    outer: while (line_iter.next()) |line| {
        i += 1;
        if (line.len == 0 or line[0] == '#') continue;

        test_string.clearRetainingCapacity();

        var word_iter = std.mem.splitScalar(u8, line, ' ');
        while (word_iter.next()) |hex| {
            const val = std.fmt.parseInt(u32, hex, 16) catch unreachable;
            if (0xD800 <= val and val <= 0xDFFF) continue :outer; // Surrogate code points

            var utf8_bytes: [4]u8 = undefined;
            const len = utf8Encode(@intCast(val), &utf8_bytes);
            test_string.appendSliceAssumeCapacity(utf8_bytes[0..len]);
        }

        const comparison = coll.collate(test_string.items, max_line.items);
        if (comparison == .lt) std.debug.panic("Invalid collation order at line {}\n", .{i});

        std.mem.swap(std.ArrayList(u8), &max_line, &test_string);
    }
}

fn utf8Encode(c: u21, out: []u8) u3 {
    const length: u3 = if (c < 0x80) 1 else if (c < 0x800) 2 else if (c < 0x10000) 3 else 4;

    switch (length) {
        // The pattern for each is the same
        // - Increasing the initial shift by 6 each time
        // - Each time after the first shorten the shifted
        //   value to a max of 0b111111 (63)
        1 => out[0] = @as(u8, @intCast(c)), // Can just do 0 + codepoint for initial range
        2 => {
            out[0] = @as(u8, @intCast(0b11000000 | (c >> 6)));
            out[1] = @as(u8, @intCast(0b10000000 | (c & 0b111111)));
        },
        3 => {
            out[0] = @as(u8, @intCast(0b11100000 | (c >> 12)));
            out[1] = @as(u8, @intCast(0b10000000 | ((c >> 6) & 0b111111)));
            out[2] = @as(u8, @intCast(0b10000000 | (c & 0b111111)));
        },
        4 => {
            out[0] = @as(u8, @intCast(0b11110000 | (c >> 18)));
            out[1] = @as(u8, @intCast(0b10000000 | ((c >> 12) & 0b111111)));
            out[2] = @as(u8, @intCast(0b10000000 | ((c >> 6) & 0b111111)));
            out[3] = @as(u8, @intCast(0b10000000 | (c & 0b111111)));
        },
        else => unreachable,
    }

    return length;
}

//
// Conformance tests
//

test "cldr non-ignorable" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .cldr, false, false);
    defer coll.deinit();

    conformance(alloc, "test-data/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt", &coll);
}

test "cldr shifted" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .cldr, true, false);
    defer coll.deinit();

    conformance(alloc, "test-data/CollationTest_CLDR_SHIFTED_SHORT.txt", &coll);
}

test "ducet non-ignorable" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .ducet, false, false);
    defer coll.deinit();

    conformance(alloc, "test-data/CollationTest_NON_IGNORABLE_SHORT.txt", &coll);
}

test "ducet shifted" {
    const alloc = std.testing.allocator;

    var coll = try Collator.init(alloc, .ducet, true, false);
    defer coll.deinit();

    conformance(alloc, "test-data/CollationTest_SHIFTED_SHORT.txt", &coll);
}

//
// Other tests
//

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

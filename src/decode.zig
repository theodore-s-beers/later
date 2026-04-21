const std = @import("std");

pub fn bytesToCodepoints(alloc: std.mem.Allocator, codepoints: *std.ArrayList(u32), input: []const u8) !void {
    codepoints.clearRetainingCapacity();
    try codepoints.ensureTotalCapacity(alloc, input.len);

    var state: u8 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    var i: usize = 0;
    while (i < input.len) {
        const b = input[i];
        const prev_state = state;
        const new_state = decode(&state, &codepoint, b);
        if (new_state == UTF8_REJECT) {
            codepoints.appendAssumeCapacity(REPLACEMENT);
            state = UTF8_ACCEPT;
            if (prev_state != UTF8_ACCEPT) continue; // retry same byte
        } else if (new_state == UTF8_ACCEPT) {
            codepoints.appendAssumeCapacity(codepoint);
        }
        i += 1;
    }

    // If we ended in an incomplete sequence, emit replacement
    if (state != UTF8_ACCEPT) codepoints.appendAssumeCapacity(REPLACEMENT);
}

const UTF8_ACCEPT: u8 = 0;
const UTF8_REJECT: u8 = 12;

const REPLACEMENT: u32 = 0xFFFD;

const utf8d = [364]u8{
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
    9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,
    7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,
    7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,
    8,  8,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,
    2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,
    10, 3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  4,  3,  3,
    11, 6,  6,  6,  5,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,

    0,  12, 24, 36, 60, 96, 84, 12, 12, 12, 48, 72, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 0,  12, 12, 12, 12, 12, 0,
    12, 0,  12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 24, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 12,
    12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 12, 12, 12, 12, 36,
    12, 36, 12, 12, 12, 36, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12,
    12, 36, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
};

fn decode(state: *u8, cp: *u32, byte: u8) u8 {
    const class = utf8d[byte];

    cp.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3F) | (cp.* << 6)
    else
        (@as(u32, 0xFF) >> @intCast(class)) & byte;

    const idx = @as(usize, 256) + state.* + class;
    state.* = utf8d[idx];

    return state.*;
}

test "decode 4-byte code point" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 240, 155, 178, 158 }; // 0x1BC9E

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqual(1, result.items.len);
    try testing.expectEqual(0x1BC9E, result.items[0]);
}

test "invalid sequence does not consume following ASCII bytes" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 0xC2, 0x41, 0x42 };
    const expected = [_]u32{ REPLACEMENT, 0x41, 0x42 };

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqualSlices(u32, &expected, result.items);
}

test "invalid sequence restarts from next valid starter" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 0xE2, 0x28, 0xA1 };
    const expected = [_]u32{ REPLACEMENT, 0x28, REPLACEMENT };

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqualSlices(u32, &expected, result.items);
}

test "non-shortest form sequences become replacement characters" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 0xC0, 0xAF, 0xE0, 0x80, 0xBF, 0xF0, 0x81, 0x82, 0x41 };
    const expected = [_]u32{
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        0x41,
    };

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqualSlices(u32, &expected, result.items);
}

test "surrogate UTF-8 sequences become replacement characters" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 0xED, 0xA0, 0x80, 0xED, 0xBF, 0xBF, 0xED, 0xAF, 0x41 };
    const expected = [_]u32{
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        0x41,
    };

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqualSlices(u32, &expected, result.items);
}

test "other ill-formed sequences become replacement characters" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 0xF4, 0x91, 0x92, 0x93, 0xFF, 0x41, 0x80, 0xBF, 0x42 };
    const expected = [_]u32{
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        REPLACEMENT,
        0x41,
        REPLACEMENT,
        REPLACEMENT,
        0x42,
    };

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqualSlices(u32, &expected, result.items);
}

test "truncated sequences become replacement characters" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const input = [_]u8{ 0xE1, 0x80, 0xE2, 0xF0, 0x91, 0x92, 0xF1, 0xBF, 0x41 };
    const expected = [_]u32{ REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT, 0x41 };

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, &input);

    try testing.expectEqualSlices(u32, &expected, result.items);
}

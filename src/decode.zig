const std = @import("std");

pub fn bytesToCodepoints(alloc: std.mem.Allocator, codepoints: *std.ArrayList(u32), input: []const u8) !void {
    codepoints.clearRetainingCapacity();
    try codepoints.ensureTotalCapacity(alloc, input.len);

    var state: u8 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    var i: usize = 0;
    while (i < input.len) {
        const prev_state = state;
        const new_state = decode(&state, &codepoint, input[i]);

        if (new_state == UTF8_REJECT) {
            codepoints.appendAssumeCapacity(REPLACEMENT);
            state = UTF8_ACCEPT;
            if (prev_state != UTF8_ACCEPT) continue; // Retry same byte
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

//
// Tests
//

fn expectDecoded(input: []const u8, expected: []const u32) !void {
    const testing = std.testing;
    const alloc = testing.allocator;

    var result = std.ArrayList(u32).empty;
    defer result.deinit(alloc);

    try bytesToCodepoints(alloc, &result, input);
    try testing.expectEqualSlices(u32, expected, result.items);
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
    const input = [_]u8{ 0xC2, 0x41, 0x42 };
    const expected = [_]u32{ REPLACEMENT, 0x41, 0x42 };

    try expectDecoded(&input, &expected);
}

test "invalid sequence restarts from next valid starter" {
    const input = [_]u8{ 0xE2, 0x28, 0xA1 };
    const expected = [_]u32{ REPLACEMENT, 0x28, REPLACEMENT };

    try expectDecoded(&input, &expected);
}

test "non-shortest form sequences become replacement characters" {
    const input = [_]u8{ 0xC0, 0xAF, 0xE0, 0x80, 0xBF, 0xF0, 0x81, 0x82, 0x41 };
    const expected = [_]u32{
        REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT,
        REPLACEMENT, REPLACEMENT, REPLACEMENT, 0x41,
    };

    try expectDecoded(&input, &expected);
}

test "surrogate UTF-8 sequences become replacement characters" {
    const input = [_]u8{ 0xED, 0xA0, 0x80, 0xED, 0xBF, 0xBF, 0xED, 0xAF, 0x41 };
    const expected = [_]u32{
        REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT,
        REPLACEMENT, REPLACEMENT, REPLACEMENT, 0x41,
    };

    try expectDecoded(&input, &expected);
}

test "other ill-formed sequences become replacement characters" {
    const input = [_]u8{ 0xF4, 0x91, 0x92, 0x93, 0xFF, 0x41, 0x80, 0xBF, 0x42 };
    const expected = [_]u32{
        REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT, 0x41,
        REPLACEMENT, REPLACEMENT, 0x42,
    };

    try expectDecoded(&input, &expected);
}

test "truncated sequences become replacement characters" {
    const input = [_]u8{ 0xE1, 0x80, 0xE2, 0xF0, 0x91, 0x92, 0xF1, 0xBF, 0x41 };
    const expected = [_]u32{ REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT, 0x41 };

    try expectDecoded(&input, &expected);
}

test "decode boundary valid UTF-8 scalars" {
    const input = [_]u8{
        0x00, 0x7F, 0xC2, 0x80, 0xDF, 0xBF, 0xE0, 0xA0,
        0x80, 0xEF, 0xBF, 0xBF, 0xF0, 0x90, 0x80, 0x80,
        0xF4, 0x8F, 0xBF, 0xBF,
    };
    const expected = [_]u32{ 0x00, 0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x10FFFF };

    try expectDecoded(&input, &expected);
}

test "decode mixed valid and invalid UTF-8 stream" {
    const input = [_]u8{ 0x41, 0xC2, 0x42, 0xE2, 0x82, 0xAC, 0x80, 0xF0, 0x9F, 0x98, 0x80 };
    const expected = [_]u32{ 0x41, REPLACEMENT, 0x42, 0x20AC, REPLACEMENT, 0x1F600 };

    try expectDecoded(&input, &expected);
}

test "out of range UTF-8 prefix does not consume following bytes" {
    const input = [_]u8{ 0xF4, 0x90, 0x80, 0x80 };
    const expected = [_]u32{ REPLACEMENT, REPLACEMENT, REPLACEMENT, REPLACEMENT };

    try expectDecoded(&input, &expected);
}

test "truncated sequences at EOF emit one replacement each" {
    try expectDecoded(&[_]u8{0xC2}, &[_]u32{REPLACEMENT});
    try expectDecoded(&[_]u8{ 0xE1, 0x80 }, &[_]u32{REPLACEMENT});
    try expectDecoded(&[_]u8{ 0xF1, 0x80, 0x80 }, &[_]u32{REPLACEMENT});
}

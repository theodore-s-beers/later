const std = @import("std");

const ccc = @import("ccc");
const implicit = @import("implicit.zig");

pub fn cccSequenceOk(test_range: []u32) bool {
    var max_cc: u8 = 0;

    for (test_range) |elem| {
        const cc = ccc.getCombiningClass(elem);
        if (cc == 0 or cc <= max_cc) return false;

        max_cc = cc;
    }

    return true;
}

pub fn cmp(comptime T: type, a: T, b: T) std.math.Order {
    if (a < b)
        return .lt
    else if (a > b)
        return .gt
    else
        return .eq;
}

pub fn cmpArray(comptime T: type, a: []const T, b: []const T) std.math.Order {
    if (std.mem.eql(T, a, b)) return .eq;

    const n = @min(a.len, b.len);
    for (0..n) |i| {
        if (a[i] < b[i]) {
            return .lt;
        } else if (a[i] > b[i]) {
            return .gt;
        }
    }

    if (a.len < b.len) return .lt else return .gt;
}

pub fn fillWeights(
    cea: *std.ArrayList(u32),
    row: []const u32,
    i: *usize,
    shifting: bool,
    last_variable: *bool,
) void {
    if (shifting) {
        for (row) |weights| {
            cea.items[i.*] = shiftWeights(weights, last_variable);
            i.* += 1;
        }
    } else {
        for (row) |weights| {
            cea.items[i.*] = weights;
            i.* += 1;
        }
    }
}

pub fn growList(alloc: std.mem.Allocator, cea: *std.ArrayList(u32), i: usize) !void {
    const l = cea.items.len;

    // U+FDFA has 18 sets of collation weights
    // We also need one spot for the sentinel value; round up to 20
    if (l - i < 20) try cea.resize(alloc, l * 2);
}

pub fn handleImplicitWeights(cea: *std.ArrayList(u32), cp: u32, i: *usize) void {
    cea.items[i.*] = implicitA(cp);
    i.* += 1;

    cea.items[i.*] = implicitB(cp);
    i.* += 1;
}

pub fn handleLowWeights(
    cea: *std.ArrayList(u32),
    weights: u32,
    i: *usize,
    shifting: bool,
    last_variable: *bool,
) void {
    cea.items[i.*] = switch (shifting) {
        true => shiftWeights(weights, last_variable),
        false => weights,
    };

    i.* += 1;
}

pub fn implicitA(cp: u32) u32 {
    const pair = implicit.weights(cp);
    return packWeights(false, @intCast(pair[0]), 32, 2);
}

pub fn implicitB(cp: u32) u32 {
    const pair = implicit.weights(cp);
    return packWeights(false, @intCast(pair[1]), 0, 0);
}

pub fn packWeights(variable: bool, primary: u16, secondary: u16, tertiary: u8) u32 {
    const upper: u32 = (@as(u32, primary) << 16);
    const v_int: u16 = @intFromBool(variable);
    const lower: u16 = (v_int << 15) | (@as(u16, tertiary) << 9) | secondary;
    return upper | lower;
}

pub fn removePulled(
    char_vals: *std.ArrayList(u32),
    i: usize,
    input_length: *usize,
    try_two: bool,
) void {
    _ = char_vals.orderedRemove(i);
    input_length.* -= 1;

    if (try_two) {
        _ = char_vals.orderedRemove(i - 1);
        input_length.* -= 1;
    }
}

pub fn shiftWeights(weights: u32, last_variable: *bool) u32 {
    const unpacked = unpackWeights(weights);
    const variable: bool = unpacked.@"0";
    const primary: u16 = unpacked.@"1";
    const tertiary: u16 = unpacked.@"3";

    if (variable) {
        last_variable.* = true;
        return packWeights(true, primary, 0, 0);
    } else if (primary == 0 and (tertiary == 0 or last_variable.*)) {
        return 0;
    } else {
        last_variable.* = false;
        return weights;
    }
}

pub fn unpackWeights(packed_weights: u32) struct { bool, u16, u16, u16 } {
    const primary: u16 = @intCast(packed_weights >> 16);

    const lower: u16 = @intCast(packed_weights & 0xFFFF);
    const variable = lower >> 15 == 1;
    const secondary = lower & 0b1_1111_1111;
    const tertiary = (lower >> 9) & 0b11_1111;

    return .{ variable, primary, secondary, tertiary };
}

test "Unicode 18 implicit weights respect script assignments and gaps" {
    const cases = [_]struct { u32, u32, u32 }{
        .{ 0x18800, 0xFB01, 0x8000 }, // Tangut components have their own base.
        .{ 0x18D80, 0xFB01, 0x8580 }, // Supplement shares the original offset.
        .{ 0x1B170, 0xFB02, 0x8000 }, // Nushu.
        .{ 0x18CFF, 0xFB03, 0x81FF }, // Assigned Khitan character after a gap.
        .{ 0x18E00, 0xFB04, 0x8000 }, // Jurchen.
        .{ 0x191A0, 0xFB04, 0x83A0 }, // Jurchen radicals.
        .{ 0x3D000, 0xFB05, 0x8000 }, // Seal.
        .{ 0x2B81E, 0xFB85, 0xB81E }, // Newly assigned Han, formerly special-cased.
        .{ 0x33479, 0xFB86, 0xB479 }, // Last assigned CJK extension J character.
        .{ 0x3347A, 0xFBC6, 0xB47A }, // Unassigned following it.
        .{ 0x18DF3, 0xFBC3, 0x8DF3 }, // Unassigned Tangut supplement slot.
    };
    for (cases) |case| {
        try std.testing.expectEqual(packWeights(false, @intCast(case[1]), 32, 2), implicitA(case[0]));
        try std.testing.expectEqual(packWeights(false, @intCast(case[2]), 0, 0), implicitB(case[0]));
    }
}

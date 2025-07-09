const std = @import("std");
const consts = @import("consts");

const Collator = @import("collator").Collator;

pub fn cccSequenceOk(coll: *Collator, test_range: []u32) !bool {
    var max_ccc: u8 = 0;

    for (test_range) |elem| {
        const ccc = try coll.getCCC(elem) orelse 0;
        if (ccc == 0 or ccc <= max_ccc) return false;

        max_ccc = ccc;
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

pub fn growList(cea: *std.ArrayList(u32), i: usize) !void {
    const l = cea.items.len;

    // U+FDFA has 18 sets of collation weights
    // We also need one spot for the sentinel value; round up to 20
    if (l - i < 20) try cea.resize(l * 2);
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
    const aaaa = blk: {
        if (std.mem.indexOfScalar(u32, &consts.INCLUDED_UNASSIGNED, cp)) |_| {
            break :blk 0xFBC0 + (cp >> 15);
        }

        if ((cp >= 0x3400 and cp <= 0x4DBF) or
            (cp >= 0x20000 and cp <= 0x2A6DF) or
            (cp >= 0x2A700 and cp <= 0x2EE5D) or
            (cp >= 0x30000 and cp <= 0x323AF))
        {
            break :blk 0xFB80 + (cp >> 15); // CJK2
        }

        if ((cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0xF900 and cp <= 0xFAFF)) {
            break :blk 0xFB40 + (cp >> 15); // CJK1
        }

        if ((cp >= 0x17000 and cp <= 0x18AFF) or (cp >= 0x18D00 and cp <= 0x18D8F)) {
            break :blk 0xFB00; // Tangut
        }

        if (cp >= 0x18B00 and cp <= 0x18CFF) break :blk 0xFB02; // Khitan
        if (cp >= 0x1B170 and cp <= 0x1B2FF) break :blk 0xFB01; // Nushu
        break :blk 0xFBC0 + (cp >> 15); // Unassigned
    };

    return packWeights(false, @intCast(aaaa), 32, 2);
}

pub fn implicitB(cp: u32) u32 {
    var bbbb = blk: {
        if (std.mem.indexOfScalar(u32, &consts.INCLUDED_UNASSIGNED, cp)) |_|
            break :blk cp & 0x7FFF;

        if ((cp >= 0x17000 and cp <= 0x18AFF) or (cp >= 0x18D00 and cp <= 0x18D8F)) {
            break :blk cp - 0x17000; // Tangut
        }

        if (cp >= 0x18B00 and cp <= 0x18CFF) break :blk cp - 0x18B00; // Khitan
        if (cp >= 0x1B170 and cp <= 0x1B2FF) break :blk cp - 0x1B170; // Nushu
        break :blk cp & 0x7FFF; // CJK1, CJK2, unass.
    };

    bbbb |= 0x8000; // BBBB always bitwise ORed with this value
    return packWeights(false, @intCast(bbbb), 0, 0);
}

pub fn packCodePoints(code_points: []const u32) u64 {
    switch (code_points.len) {
        2 => {
            return (@as(u64, code_points[0]) << 21) | @as(u64, code_points[1]);
        },
        3 => {
            return (@as(u64, code_points[0]) << 42) |
                (@as(u64, code_points[1]) << 21) |
                @as(u64, code_points[2]);
        },
        else => unreachable,
    }
}

pub fn packWeights(variable: bool, primary: u16, secondary: u16, tertiary: u8) u32 {
    const upper: u32 = (@as(u32, primary) << 16);
    const v_int: u16 = @intFromBool(variable);
    const lower: u16 = (v_int << 15) | (@as(u16, tertiary) << 9) | secondary;
    return upper | @as(u32, lower);
}

pub fn removePulled(char_vals: *std.ArrayList(u32), i: usize, input_length: *usize, try_two: bool) void {
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

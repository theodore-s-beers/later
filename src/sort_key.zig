const std = @import("std");
const util = @import("util");

pub fn cmpIncremental(a_cea: []const u32, b_cea: []const u32, shifting: bool) std.math.Order {
    if (shifting) {
        if (comparePrimaryShifting(a_cea, b_cea)) |o| return o;
    } else if (comparePrimary(a_cea, b_cea)) |o| return o;

    if (compareSecondary(a_cea, b_cea)) |o| return o;

    if (compareTertiary(a_cea, b_cea)) |o| return o;

    // If not shifting, stop here
    if (!shifting) return .eq;

    if (compareQuaternary(a_cea, b_cea)) |o| return o;

    // If we got to this point, return Equal. The efficiency of processing and comparing sort keys
    // incrementally, for both strings at once, relies on the rarity of needing to continue all the
    // way through tertiary or quaternary weights. (Remember, there are two earlier fast paths for
    // equal strings -- one before normalization, one after.)
    return .eq;
}

//
// Level-specific comparison
//

fn comparePrimary(a_cea: []const u32, b_cea: []const u32) ?std.math.Order {
    var i_a: usize = 0;
    var i_b: usize = 0;

    while (true) {
        const a_p = nextValidPrimary(a_cea, &i_a);
        const b_p = nextValidPrimary(b_cea, &i_b);

        if (a_p != b_p) return util.cmp(u16, a_p, b_p);
        if (a_p == 0) return null; // i.e., both exhausted
    }

    unreachable;
}

fn comparePrimaryShifting(a_cea: []const u32, b_cea: []const u32) ?std.math.Order {
    var i_a: usize = 0;
    var i_b: usize = 0;

    while (true) {
        const a_p = nextValidPrimaryShifting(a_cea, &i_a);
        const b_p = nextValidPrimaryShifting(b_cea, &i_b);

        if (a_p != b_p) return util.cmp(u16, a_p, b_p);
        if (a_p == 0) return null; // i.e., both exhausted
    }

    unreachable;
}

fn compareSecondary(a_cea: []const u32, b_cea: []const u32) ?std.math.Order {
    var i_a: usize = 0;
    var i_b: usize = 0;

    while (true) {
        const a_s = nextValidSecondary(a_cea, &i_a);
        const b_s = nextValidSecondary(b_cea, &i_b);

        if (a_s != b_s) return util.cmp(u16, a_s, b_s);
        if (a_s == 0) return null; // i.e., both exhausted
    }

    unreachable;
}

fn compareTertiary(a_cea: []const u32, b_cea: []const u32) ?std.math.Order {
    var i_a: usize = 0;
    var i_b: usize = 0;

    while (true) {
        const a_t = nextValidTertiary(a_cea, &i_a);
        const b_t = nextValidTertiary(b_cea, &i_b);

        if (a_t != b_t) return util.cmp(u16, a_t, b_t);
        if (a_t == 0) return null; // i.e., both exhausted
    }

    unreachable;
}

fn compareQuaternary(a_cea: []const u32, b_cea: []const u32) ?std.math.Order {
    var i_a: usize = 0;
    var i_b: usize = 0;

    while (true) {
        const a_q = nextValidPrimary(a_cea, &i_a);
        const b_q = nextValidPrimary(b_cea, &i_b);

        if (a_q != b_q) return util.cmp(u16, a_q, b_q);
        if (a_q == 0) return null; // i.e., both exhausted
    }

    unreachable;
}

//
// Iterators
//

fn nextValidPrimary(cea: []const u32, i: *usize) u16 {
    while (i.* < cea.len) {
        const nextWeights = cea[i.*];
        if (nextWeights == std.math.maxInt(u32)) return 0;

        const nextPrimary = primary(nextWeights);
        i.* += 1;

        if (nextPrimary != 0) return nextPrimary;
    }

    return 0;
}

fn nextValidPrimaryShifting(cea: []const u32, i: *usize) u16 {
    while (i.* < cea.len) {
        const nextWeights = cea[i.*];
        if (nextWeights == std.math.maxInt(u32)) return 0;

        if (variability(nextWeights)) {
            i.* += 1;
            continue;
        }

        const nextPrimary = primary(nextWeights);
        i.* += 1;

        if (nextPrimary != 0) return nextPrimary;
    }

    return 0;
}

fn nextValidSecondary(cea: []const u32, i: *usize) u16 {
    while (i.* < cea.len) {
        const nextWeights = cea[i.*];
        if (nextWeights == std.math.maxInt(u32)) return 0;

        const nextSecondary = secondary(nextWeights);
        i.* += 1;

        if (nextSecondary != 0) return nextSecondary;
    }

    return 0;
}

fn nextValidTertiary(cea: []const u32, i: *usize) u16 {
    while (i.* < cea.len) {
        const nextWeights = cea[i.*];
        if (nextWeights == std.math.maxInt(u32)) return 0;

        const nextTertiary = tertiary(nextWeights);
        i.* += 1;

        if (nextTertiary != 0) return nextTertiary;
    }

    return 0;
}

//
// Weight extraction
//

pub fn variability(weights: u32) bool {
    return weights & (1 << 15) != 0;
}

pub fn primary(weights: u32) u16 {
    return @intCast(weights >> 16);
}

pub fn secondary(weights: u32) u16 {
    return @intCast((weights & 0xFFFF) & 0b1_1111_1111);
}

pub fn tertiary(weights: u32) u16 {
    return @intCast(((weights & 0xFFFF) >> 9) & 0b11_1111);
}

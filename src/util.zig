const std = @import("std");

pub fn cmp(comptime T: type, a: []const T, b: []const T) std.math.Order {
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

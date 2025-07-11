const std = @import("std");
const util = @import("util");

pub fn tryAscii(a: []const u32, b: []const u32) ?std.math.Order {
    var backup: ?std.math.Order = null;
    var i: usize = 0;

    while (i < a.len and i < b.len) : (i += 1) {
        const a_char = a[i];
        if (!asciiAlphanumeric(a_char)) return null;

        const b_char = b[i];
        if (!asciiAlphanumeric(b_char)) return null;

        if (a_char == b_char) continue;

        const a_folded = if (a_char > 0x5A) a_char - 0x20 else a_char;
        const b_folded = if (b_char > 0x5A) b_char - 0x20 else b_char;

        if (a_folded == b_folded) {
            if (backup == null) backup = util.cmp(u32, b_char, a_char);
            continue;
        }

        return util.cmp(u32, a_folded, b_folded);
    }

    if (a.len != b.len) return util.cmp(usize, a.len, b.len);
    return backup;
}

// ASCII range, not punctuation or symbols
fn asciiAlphanumeric(c: u32) bool {
    return (0x30 <= c and c <= 0x7A) and
        !(0x3A <= c and c <= 0x40) and
        !(0x5B <= c and c <= 0x60);
}

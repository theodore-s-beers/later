const std = @import("std");
const Collator = @import("collator").Collator;

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

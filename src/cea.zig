const std = @import("std");

const ccc = @import("ccc");
const sort_key = @import("sort_key");
const util = @import("util");

const Collator = @import("collator").Collator;

// A primary difference is decisive. On a tie, both CEA buffers are complete
// and sentinel-terminated, ready for comparison at the remaining levels.
pub fn comparePrimaryStreaming(coll: *Collator, offset: usize) !?std.math.Order {
    var a = Cursor.init(coll, offset, false);
    var b = Cursor.init(coll, offset, true);

    while (true) {
        const a_primary = try a.nextPrimary();
        const b_primary = try b.nextPrimary();
        if (a_primary != b_primary) return util.cmp(u16, a_primary, b_primary);
        if (a_primary == 0) return null;
    }
}

const Cursor = struct {
    coll: *Collator,
    chars: *std.ArrayList(u32),
    weights: *std.ArrayList(u32),
    input_len: usize,
    left: usize,
    cea_len: usize = 0,
    read_index: usize = 0,
    last_variable: bool = false,

    fn init(coll: *Collator, offset: usize, side_b: bool) Cursor {
        const chars = if (side_b) &coll.b_chars else &coll.a_chars;
        return .{
            .coll = coll,
            .chars = chars,
            .weights = if (side_b) &coll.b_cea else &coll.a_cea,
            .input_len = chars.items.len,
            .left = offset,
        };
    }

    fn nextPrimary(self: *Cursor) !u16 {
        while (true) {
            while (self.read_index < self.cea_len) {
                const weights = self.weights.items[self.read_index];
                self.read_index += 1;
                if (self.coll.shifting and sort_key.variability(weights)) continue;
                const primary = sort_key.primary(weights);
                if (primary != 0) return primary;
            }

            if (self.left == self.input_len) {
                self.weights.items[self.cea_len] = std.math.maxInt(u32);
                return 0;
            }

            try self.generateNext();
        }
    }

    fn generateNext(self: *Cursor) !void {
        const coll = self.coll;
        const char_vals = self.chars;
        const cea = self.weights;
        const left_val = char_vals.items[self.left];

        try util.growList(coll.alloc, cea, self.cea_len);

        //
        // OUTCOME 1
        //
        // The code point was low, so we could draw from a small map that associates one u32 with
        // one set of weights. Then we fill in the weights, shifting if necessary. This is the path
        // that catches (most) ASCII characters present in not-completely-ASCII strings.
        //
        if (left_val < 0xB7 and left_val != 0x6C and left_val != 0x4C) {
            const weights = coll.low_table[left_val]; // Guaranteed to succeed
            util.handleLowWeights(cea, weights, &self.cea_len, coll.shifting, &self.last_variable);
            self.left += 1;
            return;
        }

        // At this point, we aren't dealing with a low code point

        // The indexed entry holds both the single-character row and contraction metadata.
        const table = &coll.collation.?;
        const entry = table.entry(left_val);
        const lookahead = table.maxLen(entry);

        // If lookahead is 1, or if this is the last item in the vec, we'll take an easier path
        const check_multi = lookahead > 1 and self.input_len - self.left > 1;

        if (!check_multi) {
            //
            // OUTCOME 2
            //
            // We only had to check for a single code point, and found it, so we can fill in the
            // weights and continue. This is a relatively fast path.
            //
            if (table.simpleRow(entry)) |row| {
                util.fillWeights(cea, row, &self.cea_len, coll.shifting, &self.last_variable);
                self.left += 1;
                return;
            }

            //
            // OUTCOME 3
            //
            // We checked for a single code point and didn't find it. That means it's unlisted. We
            // then calculate implicit weights, push them, and move on. I used to think there were
            // multiple paths to the "implicit weights" case, but it seems not.
            //
            util.handleImplicitWeights(cea, left_val, &self.cea_len);

            self.left += 1;
            return;
        }

        // Here we consider multi-code-point matches, if possible

        // Don't look past the end of the vec
        var right: usize = @min(self.input_len, self.left + lookahead);

        while (right > self.left) {
            if (right - self.left == 1) {
                // If right - self.left == 1 (which cannot be the case in the first iteration), attempts
                // to find a multi-code-point match have failed. So we pull the value(s) for the
                // first code point from its indexed entry. It's guaranteed to be there.
                const row = table.simpleRow(entry) orelse unreachable;

                // If we found it, we do still need to check for discontiguous matches
                // Determine how much further right to look
                var max_right: usize = if (self.input_len - right >= 3)
                    right + 2
                else if (self.input_len - right == 2)
                    right + 1
                else
                    right; // Skip the loop below; there will be no discontiguous match

                var try_two = max_right - right == 2 and lookahead == 3;

                while (max_right > right) {
                    // Make sure the sequence of CCC values is kosher
                    const test_range = char_vals.items[right .. max_right + 1];

                    if (!util.cccSequenceOk(test_range)) {
                        try_two = false; // Can forget about try_two in this case
                        max_right -= 1;
                        continue;
                    }

                    // Having made it this far, we can test a new subset, adding later char(s)
                    const new_subset: []const u32 = if (try_two)
                        &[3]u32{ left_val, char_vals.items[max_right - 1], char_vals.items[max_right] }
                    else
                        &[2]u32{ left_val, char_vals.items[max_right] };

                    //
                    // OUTCOME 6
                    //
                    // We found a discontiguous match after a single code point. This is a bad path,
                    // since it implies that we: checked for a multi-code-point match; didn't find
                    // one; fell back to the initial code point; checked for discontiguous matches;
                    // and found something. Anyway, fill in the weights...
                    //
                    if (table.contractionRow(entry, new_subset[1..])) |new_row| {
                        util.fillWeights(cea, new_row, &self.cea_len, coll.shifting, &self.last_variable);

                        // Remove the later char(s) used for the discontiguous match
                        util.removePulled(char_vals, max_right, &self.input_len, try_two);

                        self.left += 1;
                        return;
                    }

                    // If we tried for two, don't decrement max_right yet; inner loop will re-run
                    if (try_two) {
                        try_two = false;
                    } else {
                        max_right -= 1; // Otherwise decrement; inner loop *may* re-run
                    }
                }

                //
                // OUTCOME 7
                //
                // We checked for a multi-code-point match; failed to find one; fell back to the
                // initial code point; possibly checked for discontiguous matches; and, if so, did
                // not find any. This can be the worst path. Fill in the weights...
                //
                util.fillWeights(cea, row, &self.cea_len, coll.shifting, &self.last_variable);
                self.left += 1;
                return;
            }

            // At this point, we're trying to find a slice; this comes "before" the section above
            const subset = char_vals.items[self.left..right];

            if (table.contractionRow(entry, subset[1..])) |row| {
                // If we found it, we may need to check for a discontiguous match. But that's only
                // if we matched on a set of two code points; and we'll only skip over one to find a
                // possible third.
                const try_discont = subset.len == 2 and right + 1 < self.input_len;

                if (try_discont) {
                    // Need to make sure the sequence of CCCs is kosher
                    const cc_a = ccc.getCombiningClass(char_vals.items[right]);
                    const cc_b = ccc.getCombiningClass(char_vals.items[right + 1]);

                    if (cc_a > 0 and cc_b > cc_a) {
                        // Having made it this far, we can test a new subset, adding the later char.
                        // Again, this only happens if we found a match of two code points and want
                        // to add a third; so we can be oddly specific.
                        const new_subset = [3]u32{ subset[0], subset[1], char_vals.items[right + 1] };

                        //
                        // OUTCOME 4
                        //
                        // We checked for a multi-code-point match; found one; then checked for a
                        // larger discontiguous match; and again found one. For a complicated case,
                        // this is a good path. Fill in the weights...
                        //
                        if (table.get3(entry, new_subset[1], new_subset[2])) |new_row| {
                            util.fillWeights(cea, new_row, &self.cea_len, coll.shifting, &self.last_variable);

                            // Remove the later char used for the discontiguous match
                            util.removePulled(char_vals, right + 1, &self.input_len, false);

                            self.left += right - self.left;
                            return;
                        }
                    }
                }

                //
                // OUTCOME 5
                //
                // We checked for a multi-code-point match; found one; then checked for a larger
                // discontiguous match; and did not find any. An ok path? Fill in the weights...
                //
                util.fillWeights(cea, row, &self.cea_len, coll.shifting, &self.last_variable);
                self.left += right - self.left; // NB, we increment here by a variable amount
                return;
            }

            // Shorten slice to try again
            right -= 1;
        }

        // Every matching case returns after consuming one character or contraction.
        unreachable;
    }
};

test "streaming primary comparison stops before long suffixes" {
    const alloc = std.testing.allocator;
    var coll = try Collator.initDefault(alloc);
    defer coll.deinit();

    try coll.a_chars.appendSlice(alloc, &.{ 'z', 0xE9 });
    try coll.b_chars.appendSlice(alloc, &.{ 'z', 0xF6 });
    try coll.a_chars.appendSlice(alloc, &@as([128]u32, @splat('x')));
    try coll.b_chars.appendSlice(alloc, &@as([128]u32, @splat('y')));
    const a_len = coll.a_cea.items.len;
    const b_len = coll.b_cea.items.len;

    // Start after the shared prefix. Neither CEA needs to grow for the long tail.
    try std.testing.expectEqual(std.math.Order.lt, (try comparePrimaryStreaming(&coll, 1)).?);
    try std.testing.expectEqual(a_len, coll.a_cea.items.len);
    try std.testing.expectEqual(b_len, coll.b_cea.items.len);

    var cursor = Cursor.init(&coll, 1, false);
    try std.testing.expect(try cursor.nextPrimary() != 0);
    try std.testing.expectEqual(2, cursor.left);
}

test "primary ties preserve secondary tertiary and quaternary comparisons" {
    const alloc = std.testing.allocator;
    var coll = try Collator.initDefault(alloc);
    defer coll.deinit();

    const cases = .{
        .{ &[_]u32{'e'}, &[_]u32{0xE9} }, // Accent: secondary level.
        .{ &[_]u32{0xE9}, &[_]u32{0xC9} }, // Case: tertiary level.
        .{ &[_]u32{ '-', 'e' }, &[_]u32{'e'} }, // Shifted punctuation: quaternary level.
    };
    inline for (cases) |case| {
        coll.a_chars.clearRetainingCapacity();
        coll.b_chars.clearRetainingCapacity();
        try coll.a_chars.appendSlice(alloc, case[0]);
        try coll.b_chars.appendSlice(alloc, case[1]);
        try std.testing.expectEqual(null, try comparePrimaryStreaming(&coll, 0));
        try std.testing.expectEqual(std.math.Order.lt, sort_key.cmpRemaining(coll.a_cea.items, coll.b_cea.items, true));
    }
}

test "streaming handles expansions implicit weights and buffer reuse" {
    const alloc = std.testing.allocator;
    var coll = try Collator.initDefault(alloc);
    defer coll.deinit();

    // Each U+FDFA expands to 18 CEs, forcing buffer growth and resuming within rows.
    try coll.a_chars.appendSlice(alloc, &@as([5]u32, @splat(0xFDFA)));
    try coll.b_chars.appendSlice(alloc, &@as([5]u32, @splat(0xFDFA)));
    try std.testing.expectEqual(null, try comparePrimaryStreaming(&coll, 0));
    try std.testing.expectEqual(std.math.maxInt(u32), coll.a_cea.items[90]);
    try std.testing.expectEqualSlices(u32, coll.a_cea.items[0..91], coll.b_cea.items[0..91]);

    // Implicit weights need the second CE to distinguish these unassigned scalars.
    coll.a_chars.clearRetainingCapacity();
    coll.b_chars.clearRetainingCapacity();
    try coll.a_chars.append(alloc, 0x10FFFC);
    try coll.b_chars.append(alloc, 0x10FFFD);
    try std.testing.expectEqual(std.math.Order.lt, (try comparePrimaryStreaming(&coll, 0)).?);

    // A subsequent short tie must terminate before any stale expansion weights.
    coll.a_chars.items[0] = 'e';
    coll.b_chars.items[0] = 'e';
    try std.testing.expectEqual(null, try comparePrimaryStreaming(&coll, 0));
    try std.testing.expectEqual(std.math.maxInt(u32), coll.a_cea.items[1]);
    try std.testing.expectEqual(std.math.maxInt(u32), coll.b_cea.items[1]);
    try std.testing.expectEqual(std.math.Order.eq, sort_key.cmpRemaining(coll.a_cea.items, coll.b_cea.items, true));
}

test "Unicode 18 DUCET pulls both Tibetan contraction marks" {
    var coll = try Collator.init(std.testing.allocator, .ducet, false, false);
    defer coll.deinit();
    // Overlay (CCC 1) does not block the Tibetan marks (CCC 129, 130).
    try coll.a_chars.appendSlice(coll.alloc, &.{ 0xFB2, 0x334, 0xF71, 0xF80 });
    var cursor = Cursor.init(&coll, 0, false);
    while (try cursor.nextPrimary() != 0) {}
    const table = &coll.collation.?;
    const contraction = table.get3(table.entry(0xFB2), 0xF71, 0xF80).?;
    const overlay = coll.getSingle(0x334).?;
    try std.testing.expectEqualSlices(u32, contraction, coll.a_cea.items[0..contraction.len]);
    try std.testing.expectEqualSlices(u32, overlay, coll.a_cea.items[contraction.len..][0..overlay.len]);
    try std.testing.expectEqual(contraction.len + overlay.len, cursor.cea_len);
}

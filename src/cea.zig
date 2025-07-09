const std = @import("std");
const ArrayList = std.ArrayList;

const consts = @import("consts");
const util = @import("util");

const Collator = @import("collator").Collator;

pub fn generateCEA(
    coll: *Collator,
    cea: *ArrayList(u32),
    char_vals: *ArrayList(u32),
) !void {
    var input_length: usize = char_vals.items.len;

    var left: usize = 0;
    var cea_idx: usize = 0;
    var last_variable = false;

    // We spend essentially the entire function in this loop
    outer: while (left < input_length) {
        const left_val = char_vals.items[left];

        try util.growList(cea, cea_idx);

        //
        // OUTCOME 1
        //
        // The code point was low, so we could draw from a small map that associates one u32 with
        // one set of weights. Then we fill in the weights, shifting if necessary. This is the path
        // that catches (most) ASCII characters present in not-completely-ASCII strings.
        //
        if (left_val < 0x00B7 and left_val != 0x006C and left_val != 0x004C) {
            const weights = coll.low_table[left_val]; // Guaranteed to succeed
            util.handleLowWeights(cea, weights, &cea_idx, coll.shifting, &last_variable);
            left += 1;
            continue; // To the next outer loop iteration...
        }

        // At this point, we aren't dealing with a low code point

        // Set lookahead depending on left_val. We need 3 in a few cases; 2 in several dozen cases;
        // and 1 otherwise.
        const lookahead: usize = blk: {
            if (std.mem.indexOfScalar(u32, &consts.NEED_THREE, left_val)) |_| {
                break :blk 3;
            } else if (std.mem.indexOfScalar(u32, &consts.NEED_TWO, left_val)) |_| {
                break :blk 2;
            } else break :blk 1;
        };

        // If lookahead is 1, or if this is the last item in the vec, we'll take an easier path
        const check_multi = lookahead > 1 and input_length - left > 1;

        if (!check_multi) {
            //
            // OUTCOME 2
            //
            // We only had to check for a single code point, and found it, so we can fill in the
            // weights and continue. This is a relatively fast path.
            //
            if (try coll.getSingle(left_val)) |row| {
                util.fillWeights(cea, row, &cea_idx, coll.shifting, &last_variable);
                left += 1;
                continue; // To the next outer loop iteration...
            }

            //
            // OUTCOME 3
            //
            // We checked for a single code point and didn't find it. That means it's unlisted. We
            // then calculate implicit weights, push them, and move on. I used to think there were
            // multiple paths to the "implicit weights" case, but it seems not.
            //
            util.handleImplicitWeights(cea, left_val, &cea_idx);

            left += 1;
            continue; // To the next outer loop iteration...
        }

        // Here we consider multi-code-point matches, if possible

        // Don't look past the end of the vec
        var right: usize = @min(input_length, left + lookahead);

        while (right > left) {
            if (right - left == 1) {
                // If right - left == 1 (which cannot be the case in the first iteration), attempts
                // to find a multi-code-point match have failed. So we pull the value(s) for the
                // first code point from the singles map. It's guaranteed to be there.
                const row = try coll.getSingle(left_val) orelse unreachable;

                // If we found it, we do still need to check for discontiguous matches
                // Determine how much further right to look
                var max_right: usize = if (input_length - right >= 3)
                    right + 2
                else if (input_length - right == 2) right + 1 else right; // Skip the loop below; there will be no discontiguous match

                var try_two = max_right - right == 2 and coll.table == .cldr;

                while (max_right > right) {
                    // Make sure the sequence of CCC values is kosher
                    const test_range = char_vals.items[right .. max_right + 1];

                    if (!try util.cccSequenceOk(coll, test_range)) {
                        try_two = false; // Can forget about try_two in this case
                        max_right -= 1;
                        continue;
                    }

                    // Having made it this far, we can test a new subset, adding later char(s)
                    const new_subset: []const u32 = if (try_two)
                        &[_]u32{ left_val, char_vals.items[max_right - 1], char_vals.items[max_right] }
                    else
                        &[_]u32{ left_val, char_vals.items[max_right] };

                    //
                    // OUTCOME 6
                    //
                    // We found a discontiguous match after a single code point. This is a bad path,
                    // since it implies that we: checked for a multi-code-point match; didn't find
                    // one; fell back to the initial code point; checked for discontiguous matches;
                    // and found something. Anyway, fill in the weights...
                    //
                    if (try coll.getMulti(util.packCodePoints(new_subset))) |new_row| {
                        util.fillWeights(cea, new_row, &cea_idx, coll.shifting, &last_variable);

                        // Remove the later char(s) used for the discontiguous match
                        util.removePulled(char_vals, max_right, &input_length, try_two);

                        left += 1;
                        continue :outer;
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
                util.fillWeights(cea, row, &cea_idx, coll.shifting, &last_variable);
                left += 1;
                continue :outer;
            }

            // At this point, we're trying to find a slice; this comes "before" the section above
            const subset = char_vals.items[left..right];

            if (try coll.getMulti(util.packCodePoints(subset))) |row| {
                // If we found it, we may need to check for a discontiguous match. But that's only
                // if we matched on a set of two code points; and we'll only skip over one to find a
                // possible third.
                const try_discont = subset.len == 2 and right + 1 < input_length;

                if (try_discont) {
                    // Need to make sure the sequence of CCCs is kosher
                    const ccc_a: u8 = try coll.getCCC(char_vals.items[right]) orelse 0;
                    const ccc_b: u8 = try coll.getCCC(char_vals.items[right + 1]) orelse 0;

                    if (ccc_a > 0 and ccc_b > ccc_a) {
                        // Having made it this far, we can test a new subset, adding the later char.
                        // Again, this only happens if we found a match of two code points and want
                        // to add a third; so we can be oddly specific.
                        const new_subset = [_]u32{ subset[0], subset[1], char_vals.items[right + 1] };

                        //
                        // OUTCOME 4
                        //
                        // We checked for a multi-code-point match; found one; then checked for a
                        // larger discontiguous match; and again found one. For a complicated case,
                        // this is a good path. Fill in the weights...
                        //
                        if (try coll.getMulti(util.packCodePoints(&new_subset))) |new_row| {
                            util.fillWeights(cea, new_row, &cea_idx, coll.shifting, &last_variable);

                            // Remove the later char used for the discontiguous match
                            util.removePulled(char_vals, right + 1, &input_length, false);

                            left += right - left;
                            continue :outer;
                        }
                    }
                }

                //
                // OUTCOME 5
                //
                // We checked for a multi-code-point match; found one; then checked for a larger
                // discontiguous match; and did not find any. An ok path? Fill in the weights...
                //
                util.fillWeights(cea, row, &cea_idx, coll.shifting, &last_variable);
                left += right - left; // NB, we increment here by a variable amount
                continue :outer;
            }

            // Shorten slice to try again
            right -= 1;
        }

        // This point is unreachable. All cases for the outer loop have been handled.
        unreachable;
    }

    // Set a high value to indicate the end of the weights
    cea.items[cea_idx] = std.math.maxInt(u32);
}

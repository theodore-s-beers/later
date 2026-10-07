const std = @import("std");
const Table = @import("collation_table").Table;

pub fn loadCollation(alloc: std.mem.Allocator, cldr: bool) error{OutOfMemory}!Table {
    const data = if (cldr) @embedFile("bin/collation_cldr.bin") else @embedFile("bin/collation.bin");
    return Table.load(alloc, data) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidData => @panic("Invalid embedded collation table"),
    };
}

fn checkCollationLoad(alloc: std.mem.Allocator, cldr: bool) !void {
    var table = try loadCollation(alloc, cldr);
    defer table.deinit(alloc);
}

test "compact collation loading cleans up every partial allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkCollationLoad, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkCollationLoad, .{true});
}

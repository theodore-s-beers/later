const std = @import("std");

pub const CollationTable = enum { ducet, cldr };

pub const MultiMap = struct {
    map: std.AutoHashMap(u64, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *MultiMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

pub const SinglesMap = struct {
    map: std.AutoHashMap(u32, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *SinglesMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

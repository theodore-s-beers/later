const std = @import("std");

const decode = @import("decode");

const Table = enum { ducet, cldr };

const Collator = struct {
    alloc: std.mem.Allocator,

    table: Table = .cldr,
    shifting: bool = true,
    tiebreak: bool = true,

    a_chars: std.ArrayList(u32),
    b_chars: std.ArrayList(u32),

    a_cea: std.ArrayList(u32),
    b_cea: std.ArrayList(u32),

    pub fn init(
        alloc: std.mem.Allocator,
        table: Table,
        shifting: bool,
        tiebreak: bool,
    ) Collator {
        return Collator{
            .alloc = alloc,
            .table = table,
            .shifting = shifting,
            .tiebreak = tiebreak,
            .a_chars = std.ArrayList(u32).init(alloc),
            .b_chars = std.ArrayList(u32).init(alloc),
            .a_cea = std.ArrayList(u32).init(alloc),
            .b_cea = std.ArrayList(u32).init(alloc),
        };
    }

    pub fn initDefault(alloc: std.mem.Allocator) Collator {
        return Collator.init(alloc, .cldr, true, true);
    }

    pub fn deinit(self: *Collator) void {
        self.a_chars.deinit();
        self.b_chars.deinit();
        self.a_cea.deinit();
        self.b_cea.deinit();
    }

    pub fn collateFallible(self: *Collator, a: []const u8, b: []const u8) !bool {
        self.a_chars.clearRetainingCapacity();
        self.b_chars.clearRetainingCapacity();

        const a_codepoints = try decode.bytesToCodepoints(self.alloc, a);
        defer self.alloc.free(a_codepoints);

        const b_codepoints = try decode.bytesToCodepoints(self.alloc, b);
        defer self.alloc.free(b_codepoints);

        try self.a_chars.appendSlice(a_codepoints);
        try self.b_chars.appendSlice(b_codepoints);

        std.debug.print("a: {any}\n", .{self.a_chars.items});
        std.debug.print("b: {any}\n", .{self.b_chars.items});

        return std.mem.eql(u8, a, b);
    }

    pub fn collate(self: *Collator, a: []const u8, b: []const u8) bool {
        return self.collateFallible(a, b) catch unreachable;
    }
};

test "collation of identical strings" {
    const allocator = std.testing.allocator;
    var collator = Collator.initDefault(allocator);
    defer collator.deinit();

    const a = "مصطفى";
    const b = "مصطفى";

    try std.testing.expect(collator.collate(a, b));
}

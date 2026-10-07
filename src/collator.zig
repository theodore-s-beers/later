const std = @import("std");

const ascii = @import("ascii");
const cea = @import("cea");
const consts = @import("consts");
const CollationData = @import("collation_table").Table;
const load = @import("load");
const normalization = @import("normalization_tables.zig");
const normalize = @import("normalize");
const prefix = @import("prefix");
const sort_key = @import("sort_key");
const types = @import("types");
const util = @import("util");

pub const Collator = struct {
    pub const InitError = error{OutOfMemory};
    pub const CollateError = error{OutOfMemory};

    alloc: std.mem.Allocator,

    table: types.CollationTable = .cldr,
    shifting: bool = true,
    tiebreak: bool = true,

    low_table: [183]u32,

    a_chars: std.ArrayList(u32),
    b_chars: std.ArrayList(u32),

    a_cea: std.ArrayList(u32),
    b_cea: std.ArrayList(u32),

    collation: ?CollationData = null,

    //
    // Init, deinit
    //

    pub fn init(
        alloc: std.mem.Allocator,
        table: types.CollationTable,
        shifting: bool,
        tiebreak: bool,
    ) InitError!Collator {
        const low_table: [183]u32 = if (table == .cldr) consts.LOW_CLDR else consts.LOW;

        var coll = Collator{
            .alloc = alloc,

            .table = table,
            .shifting = shifting,
            .tiebreak = tiebreak,

            .low_table = low_table,

            .a_chars = .empty,
            .b_chars = .empty,
            .a_cea = .empty,
            .b_cea = .empty,
        };
        errdefer coll.deinit();

        coll.a_chars = try .initCapacity(alloc, 64);
        coll.b_chars = try .initCapacity(alloc, 64);
        coll.a_cea = try .initCapacity(alloc, 64);
        coll.b_cea = try .initCapacity(alloc, 64);

        // In this case we want len == capacity
        try coll.a_cea.resize(alloc, 64);
        try coll.b_cea.resize(alloc, 64);

        coll.collation = try load.loadCollation(alloc, table == .cldr);

        return coll;
    }

    pub fn initDefault(alloc: std.mem.Allocator) InitError!Collator {
        return try Collator.init(alloc, .cldr, true, true);
    }

    pub fn deinit(self: *Collator) void {
        self.a_chars.deinit(self.alloc);
        self.b_chars.deinit(self.alloc);
        self.a_cea.deinit(self.alloc);
        self.b_cea.deinit(self.alloc);

        if (self.collation) |*data| data.deinit(self.alloc);
    }

    //
    // Collation
    //

    pub fn collate(self: *Collator, a: []const u8, b: []const u8) CollateError!std.math.Order {
        if (std.mem.eql(u8, a, b)) return .eq;

        const byte_offset = prefix.findByteOffset(self, a, b);
        return self.collateSuffixes(a, b, byte_offset);
    }

    // Keep the original bytes for the optional tiebreak even when work starts later.
    fn collateSuffixes(self: *Collator, a: []const u8, b: []const u8, byte_offset: usize) CollateError!std.math.Order {
        if (try ascii.fillCodepointsAndCompareAscii(self.alloc, &self.a_chars, &self.b_chars, a[byte_offset..], b[byte_offset..])) |ord|
            return ord;

        try normalize.makeNFD(self, &self.a_chars);
        try normalize.makeNFD(self, &self.b_chars);

        const offset = prefix.findOffset(self); // Default 0

        // Prefix trimming may reveal that one list is a prefix of the other
        if (self.a_chars.items[offset..].len == 0 or self.b_chars.items[offset..].len == 0) {
            const prefixOrd = util.cmp(usize, self.a_chars.items.len, self.b_chars.items.len);
            if (prefixOrd != .eq or !self.tiebreak) return prefixOrd;
        }

        if (try cea.comparePrimaryStreaming(self, offset)) |ord| return ord;

        const ord = sort_key.cmpRemaining(self.a_cea.items, self.b_cea.items, self.shifting);
        if (ord == .eq and self.tiebreak) return util.cmpArray(u8, a, b);

        return ord;
    }

    pub fn collateOrPanic(self: *Collator, a: []const u8, b: []const u8) std.math.Order {
        return self.collate(a, b) catch @panic("Allocation failure during collation");
    }

    //
    // Helpers for table lookups
    //

    pub fn getDecomp(self: *Collator, codepoint: u32) ?[]const u32 {
        _ = self;
        return normalization.getDecomp(codepoint);
    }

    pub fn getFCD(self: *Collator, codepoint: u32) ?u16 {
        _ = self;
        return normalization.getFCD(codepoint);
    }

    pub fn getSingle(self: *Collator, codepoint: u32) ?[]const u32 {
        if (codepoint > 0x10FFFF) return null;
        return self.collation.?.simpleRow(self.collation.?.entry(codepoint));
    }

    pub fn getVariable(self: *Collator, codepoint: u32) bool {
        _ = self;
        return normalization.isVariable(codepoint);
    }
};

test "byte prefix trimming skips decoding long shared text" {
    var coll = try Collator.initDefault(std.testing.allocator);
    defer coll.deinit();
    var a: [769]u8 = undefined;
    for (0..128) |i| @memcpy(a[i * 6 ..][0..6], "漢字");
    a[768] = 'a';
    var b = a;
    b[768] = 'b';
    try std.testing.expectEqual(std.math.Order.lt, try coll.collate(&a, &b));
    try std.testing.expectEqualSlices(u32, &.{'a'}, coll.a_chars.items);
    try std.testing.expectEqualSlices(u32, &.{'b'}, coll.b_chars.items);
}

test "byte prefix trimming agrees with untrimmed comparisons" {
    const tokens = [_][]const u8{
        "",         "a",        "A",       "l",              "L",       "-",        "\x00",
        "é",
        "e\u{301}", "\u{334}",  "\u{F73}", "\u{FB2}\u{F71}", "\u{F80}", "\u{1100}", "\u{1161}",
        "가",
        "漢字",
        "\u{FFFE}", "\u{FFFF}", "\xff",    "\xc2",           "\x80",    "\xf0\x9f", "\u{1F600}",
    };
    const prefixes = [_][]const u8{ "", "common", "a-", "é", "漢字", "\u{FB2}", "\u{FB2}\u{F71}", "\xffx", "\u{1100}", "가", "a\u{334}" };
    for ([_]types.CollationTable{ .ducet, .cldr }) |table| {
        for ([_]bool{ false, true }) |shifting| {
            for ([_]bool{ false, true }) |tiebreak| {
                var coll = try Collator.init(std.testing.allocator, table, shifting, tiebreak);
                defer coll.deinit();
                for (prefixes) |shared| {
                    for (tokens) |left| {
                        for (tokens) |right| {
                            var a_buf: [128]u8 = undefined;
                            var b_buf: [128]u8 = undefined;
                            const a = try std.fmt.bufPrint(&a_buf, "{s}{s}", .{ shared, left });
                            const b = try std.fmt.bufPrint(&b_buf, "{s}{s}", .{ shared, right });
                            const expected = try coll.collateSuffixes(a, b, 0);
                            const actual = try coll.collate(a, b);
                            if (expected != actual) std.debug.print("prefix={s}, a={x}, b={x}, table={s}, shifting={}, tiebreak={}\n", .{ shared, a, b, @tagName(table), shifting, tiebreak });
                            try std.testing.expectEqual(expected, actual);
                        }
                    }
                }
            }
        }
    }
}

test "indexed normalization lookups preserve missing and boundary values" {
    var coll = try Collator.initDefault(std.testing.allocator);
    defer coll.deinit();
    try std.testing.expectEqualSlices(u32, &.{ 0x65, 0x301 }, coll.getDecomp(0xe9).?);
    try std.testing.expectEqual(@as(?u16, 0x00e6), coll.getFCD(0xe9));
    // Undecomposed marks use the separate combining-class table.
    try std.testing.expect(coll.getFCD(0x301) == null);
    try std.testing.expect(coll.getVariable(0x20));
    try std.testing.expect(!coll.getVariable('A'));
    for ([_]u32{ 0, 'A', 0x10ffff, 0x110000, 0xffffffff }) |cp| {
        try std.testing.expect(coll.getDecomp(cp) == null);
        try std.testing.expect(coll.getFCD(cp) == null);
    }
    for ([_]u32{ 0x10ffff, 0x110000, 0xffffffff }) |cp| {
        try std.testing.expect(!coll.getVariable(cp));
    }
}

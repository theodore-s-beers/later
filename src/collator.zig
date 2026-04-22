const std = @import("std");

const ascii = @import("ascii");
const cea = @import("cea");
const consts = @import("consts");
const decode = @import("decode");
const load = @import("load");
const normalize = @import("normalize");
const prefix = @import("prefix");
const sort_key = @import("sort_key");
const types = @import("types");
const util = @import("util");

pub const Collator = struct {
    alloc: std.mem.Allocator,

    table: types.CollationTable = .cldr,
    shifting: bool = true,
    tiebreak: bool = true,

    low_table: [183]u32,

    a_chars: std.ArrayList(u32),
    b_chars: std.ArrayList(u32),

    a_cea: std.ArrayList(u32),
    b_cea: std.ArrayList(u32),

    decomp_map: ?types.SinglesMap = null,
    fcd_map: ?std.AutoHashMap(u32, u16) = null,
    multi_map: ?types.MultiMap = null,
    single_map: ?types.SinglesMap = null,
    variable_map: ?std.AutoHashMap(u32, void) = null,

    //
    // Init, deinit
    //

    pub fn init(
        alloc: std.mem.Allocator,
        table: types.CollationTable,
        shifting: bool,
        tiebreak: bool,
    ) !Collator {
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

        coll.decomp_map = try load.loadDecomp(alloc);
        coll.fcd_map = try load.loadFCD(alloc);
        coll.multi_map = try load.loadMulti(alloc, table == .cldr);
        coll.single_map = try load.loadSingle(alloc, table == .cldr);
        coll.variable_map = try load.loadVariable(alloc);

        return coll;
    }

    pub fn initDefault(alloc: std.mem.Allocator) !Collator {
        return try Collator.init(alloc, .cldr, true, true);
    }

    pub fn deinit(self: *Collator) void {
        self.a_chars.deinit(self.alloc);
        self.b_chars.deinit(self.alloc);
        self.a_cea.deinit(self.alloc);
        self.b_cea.deinit(self.alloc);

        if (self.decomp_map) |*map| map.deinit();
        if (self.fcd_map) |*map| map.deinit();
        if (self.multi_map) |*map| map.deinit();
        if (self.single_map) |*map| map.deinit();
        if (self.variable_map) |*map| map.deinit();
    }

    //
    // Collation
    //

    pub fn collate(self: *Collator, a: []const u8, b: []const u8) !std.math.Order {
        if (std.mem.eql(u8, a, b)) return .eq;

        // Decode function clears input list
        try decode.bytesToCodepoints(self.alloc, &self.a_chars, a);
        try decode.bytesToCodepoints(self.alloc, &self.b_chars, b);

        // ASCII fast path
        if (ascii.tryAscii(self.a_chars.items, self.b_chars.items)) |ord| return ord;

        try normalize.makeNFD(self, &self.a_chars);
        try normalize.makeNFD(self, &self.b_chars);

        const offset = try prefix.findOffset(self); // Default 0

        // Prefix trimming may reveal that one list is a prefix of the other
        if (self.a_chars.items[offset..].len == 0 or self.b_chars.items[offset..].len == 0) {
            const prefixOrd = util.cmp(usize, self.a_chars.items.len, self.b_chars.items.len);
            if (prefixOrd != .eq or !self.tiebreak) return prefixOrd;
        }

        try cea.generateCEA(self, offset, false); // a
        try cea.generateCEA(self, offset, true); // b

        const ord = sort_key.cmpIncremental(self.a_cea.items, self.b_cea.items, self.shifting);
        if (ord == .eq and self.tiebreak) return util.cmpArray(u8, a, b);

        return ord;
    }

    pub fn collateOrPanic(self: *Collator, a: []const u8, b: []const u8) std.math.Order {
        return self.collate(a, b) catch @panic("Allocation failure during collation");
    }

    //
    // Helpers for map lookups
    //

    pub fn getDecomp(self: *Collator, codepoint: u32) ?[]const u32 {
        return self.decomp_map.?.map.get(codepoint);
    }

    pub fn getFCD(self: *Collator, codepoint: u32) ?u16 {
        return self.fcd_map.?.get(codepoint);
    }

    pub fn getMulti(self: *Collator, codepoints: u64) ?[]const u32 {
        return self.multi_map.?.map.get(codepoints);
    }

    pub fn getSingle(self: *Collator, codepoint: u32) ?[]const u32 {
        return self.single_map.?.map.get(codepoint);
    }

    pub fn getVariable(self: *Collator, codepoint: u32) bool {
        return self.variable_map.?.contains(codepoint);
    }
};

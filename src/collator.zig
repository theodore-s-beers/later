const std = @import("std");
const AutoHashMap = std.AutoHashMap;

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

    mutex: std.Thread.Mutex = .{},

    ccc_map: ?AutoHashMap(u32, u8) = null,
    decomp_map: ?types.SinglesMap = null,
    fcd_map: ?AutoHashMap(u32, u16) = null,
    multi_map: ?types.MultiMap = null,
    single_map: ?types.SinglesMap = null,
    variable_map: ?AutoHashMap(u32, void) = null,

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

            .a_chars = std.ArrayList(u32).init(alloc),
            .b_chars = std.ArrayList(u32).init(alloc),
            .a_cea = std.ArrayList(u32).init(alloc),
            .b_cea = std.ArrayList(u32).init(alloc),
        };

        try coll.a_cea.resize(64);
        try coll.b_cea.resize(64);

        return coll;
    }

    pub fn initDefault(alloc: std.mem.Allocator) !Collator {
        return try Collator.init(alloc, .cldr, true, true);
    }

    pub fn deinit(self: *Collator) void {
        self.a_chars.deinit();
        self.b_chars.deinit();
        self.a_cea.deinit();
        self.b_cea.deinit();

        if (self.ccc_map) |*map| map.deinit();
        if (self.decomp_map) |*map| map.deinit();
        if (self.fcd_map) |*map| map.deinit();
        if (self.multi_map) |*map| map.deinit();
        if (self.single_map) |*map| map.deinit();
        if (self.variable_map) |*map| map.deinit();
    }

    //
    // Collation
    //

    pub fn collateFallible(self: *Collator, a: []const u8, b: []const u8) !std.math.Order {
        if (std.mem.eql(u8, a, b)) return .eq;

        // Decode function clears input list
        try decode.bytesToCodepoints(&self.a_chars, a);
        try decode.bytesToCodepoints(&self.b_chars, b);

        if (ascii.tryAscii(self.a_chars.items, self.b_chars.items)) |ord| return ord;

        try normalize.makeNFD(self, &self.a_chars);
        try normalize.makeNFD(self, &self.b_chars);

        if (std.mem.eql(u32, self.a_chars.items, self.b_chars.items)) {
            if (self.tiebreak) return util.cmpArray(u8, a, b);
            return util.cmpArray(u32, self.a_chars.items, self.b_chars.items);
        }

        const offset = try prefix.findOffset(self); // Default 0

        if (self.a_chars.items[offset..].len == 0 or self.b_chars.items[offset..].len == 0) {
            return util.cmp(usize, self.a_chars.items.len, self.b_chars.items.len);
        }

        try cea.generateCEA(self, &self.a_cea, &self.a_chars, offset);
        try cea.generateCEA(self, &self.b_cea, &self.b_chars, offset);

        const comparison = sort_key.compareIncremental(self.a_cea.items, self.b_cea.items, self.shifting);
        if (comparison == .eq and self.tiebreak) return util.cmpArray(u8, a, b);

        return comparison;
    }

    pub fn collate(self: *Collator, a: []const u8, b: []const u8) std.math.Order {
        return self.collateFallible(a, b) catch unreachable;
    }

    //
    // Loading data on demand
    //

    pub fn getCCC(self: *Collator, codepoint: u32) !?u8 {
        if (self.ccc_map) |*map| return map.get(codepoint);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.ccc_map == null) self.ccc_map = try load.loadCCC(self.alloc);
        return self.ccc_map.?.get(codepoint);
    }

    pub fn getDecomp(self: *Collator, codepoint: u32) !?[]const u32 {
        if (self.decomp_map) |*map| return map.map.get(codepoint);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.decomp_map == null) self.decomp_map = try load.loadDecomp(self.alloc);
        return self.decomp_map.?.map.get(codepoint);
    }

    pub fn getFCD(self: *Collator, codepoint: u32) !?u16 {
        if (self.fcd_map) |*map| return map.get(codepoint);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.fcd_map == null) self.fcd_map = try load.loadFCD(self.alloc);
        return self.fcd_map.?.get(codepoint);
    }

    pub fn getMulti(self: *Collator, codepoints: u64) !?[]const u32 {
        if (self.multi_map) |*map| return map.map.get(codepoints);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.multi_map == null)
            self.multi_map = try load.loadMulti(self.alloc, self.table == .cldr);
        return self.multi_map.?.map.get(codepoints);
    }

    pub fn getSingle(self: *Collator, codepoint: u32) !?[]const u32 {
        if (self.single_map) |*map| return map.map.get(codepoint);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.single_map == null)
            self.single_map = try load.loadSingle(self.alloc, self.table == .cldr);
        return self.single_map.?.map.get(codepoint);
    }

    pub fn getVariable(self: *Collator, codepoint: u32) !bool {
        if (self.variable_map) |*map| return map.contains(codepoint);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.variable_map == null) self.variable_map = try load.loadVariable(self.alloc);
        return self.variable_map.?.contains(codepoint);
    }
};

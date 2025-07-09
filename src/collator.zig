const std = @import("std");
const AutoHashMap = std.AutoHashMap;

const cea = @import("cea");
const consts = @import("consts");
const decode = @import("decode");
const load = @import("load");
const normalize = @import("normalize");
const types = @import("types");
const util = @import("util");

pub const Collator = struct {
    alloc: std.mem.Allocator,

    table: types.CollationTable = .cldr,
    shifting: bool = true,
    tiebreak: bool = true,

    low_table: [183]u32,
    multi_path: []const u8,
    single_path: []const u8,

    a_chars: std.ArrayList(u32),
    b_chars: std.ArrayList(u32),

    a_cea: std.ArrayList(u32),
    b_cea: std.ArrayList(u32),

    ccc_map: ?AutoHashMap(u32, u8) = null,
    decomp_map: ?types.SinglesMap = null,
    fcd_map: ?AutoHashMap(u32, u16) = null,
    multi_map: ?types.MultiMap = null,
    single_map: ?types.SinglesMap = null,
    variable_map: ?AutoHashMap(u32, void) = null,

    //
    // Init, deinit
    //

    fn init(
        alloc: std.mem.Allocator,
        table: types.CollationTable,
        shifting: bool,
        tiebreak: bool,
    ) !Collator {
        const low_table: [183]u32 = if (table == .cldr) consts.LOW_CLDR else consts.LOW;
        const multi_path = if (table == .cldr) "bin/multi_cldr.bin" else "bin/multi.bin";
        const single_path = if (table == .cldr) "bin/singles_cldr.bin" else "bin/singles.bin";

        var coll = Collator{
            .alloc = alloc,

            .table = table,
            .shifting = shifting,
            .tiebreak = tiebreak,

            .low_table = low_table,
            .multi_path = multi_path,
            .single_path = single_path,

            .a_chars = std.ArrayList(u32).init(alloc),
            .b_chars = std.ArrayList(u32).init(alloc),
            .a_cea = std.ArrayList(u32).init(alloc),
            .b_cea = std.ArrayList(u32).init(alloc),
        };

        try coll.a_cea.resize(32);
        try coll.b_cea.resize(32);

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

    fn collateFallible(self: *Collator, a: []const u8, b: []const u8) !std.math.Order {
        if (std.mem.eql(u8, a, b)) return .eq;

        const a_codepoints = try decode.bytesToCodepoints(self.alloc, a);
        defer self.alloc.free(a_codepoints);

        const b_codepoints = try decode.bytesToCodepoints(self.alloc, b);
        defer self.alloc.free(b_codepoints);

        self.a_chars.clearRetainingCapacity();
        self.b_chars.clearRetainingCapacity();

        try self.a_chars.appendSlice(a_codepoints);
        try self.b_chars.appendSlice(b_codepoints);

        try normalize.makeNFD(self, &self.a_chars);
        try normalize.makeNFD(self, &self.b_chars);

        if (std.mem.eql(u32, self.a_chars.items, self.b_chars.items)) {
            if (self.tiebreak) return util.cmp(u8, a, b);
            return util.cmp(u32, self.a_chars.items, self.b_chars.items);
        }

        try cea.generateCEA(self, &self.a_cea, &self.a_chars);
        try cea.generateCEA(self, &self.b_cea, &self.b_chars);

        // To be continued...

        std.debug.print("a: {any}\n", .{self.a_cea.items});
        std.debug.print("b: {any}\n", .{self.b_cea.items});

        // Dummy return
        return util.cmp(u32, self.a_chars.items, self.b_chars.items);
    }

    pub fn collate(self: *Collator, a: []const u8, b: []const u8) std.math.Order {
        return self.collateFallible(a, b) catch unreachable;
    }

    //
    // Loading data on demand
    //

    pub fn getCCC(self: *Collator, codepoint: u32) !?u8 {
        if (self.ccc_map == null)
            self.ccc_map = try load.loadCCC(self.alloc, "bin/ccc.bin");
        return self.ccc_map.?.get(codepoint);
    }

    pub fn getDecomp(self: *Collator, codepoint: u32) !?[]const u32 {
        if (self.decomp_map == null)
            self.decomp_map = try load.loadDecomp(self.alloc, "bin/decomp.bin");
        return self.decomp_map.?.map.get(codepoint);
    }

    pub fn getFCD(self: *Collator, codepoint: u32) !?u16 {
        if (self.fcd_map == null)
            self.fcd_map = try load.loadFCD(self.alloc, "bin/fcd.bin");
        return self.fcd_map.?.get(codepoint);
    }

    pub fn getMulti(self: *Collator, codepoints: u64) !?[]const u32 {
        if (self.multi_map == null)
            self.multi_map = try load.loadMulti(self.alloc, self.multi_path);
        return self.multi_map.?.map.get(codepoints);
    }

    pub fn getSingle(self: *Collator, codepoint: u32) !?[]const u32 {
        if (self.single_map == null)
            self.single_map = try load.loadSingle(self.alloc, self.single_path);
        return self.single_map.?.map.get(codepoint);
    }

    pub fn isVariable(self: *Collator, codepoint: u32) !bool {
        if (self.variable_map == null)
            self.variable_map = try load.loadVariable(self.alloc, "bin/variable.bin");
        return self.variable_map.?.get(codepoint) != null;
    }
};

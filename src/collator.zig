const std = @import("std");
const AutoHashMap = std.AutoHashMap;

const decode = @import("decode");
const normalize = @import("normalize");

const MultiMap = struct {
    map: std.AutoHashMap(u64, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    fn deinit(self: *MultiMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

const SinglesMap = struct {
    map: std.AutoHashMap(u32, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    fn deinit(self: *SinglesMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

const Table = enum { ducet, cldr };

pub const Collator = struct {
    alloc: std.mem.Allocator,

    table: Table = .cldr,
    shifting: bool = true,
    tiebreak: bool = true,

    a_chars: std.ArrayList(u32),
    b_chars: std.ArrayList(u32),

    a_cea: std.ArrayList(u32),
    b_cea: std.ArrayList(u32),

    ccc_map: ?AutoHashMap(u32, u8) = null,
    decomp_map: ?SinglesMap = null,
    fcd_map: ?AutoHashMap(u32, u16) = null,
    multi_map: ?MultiMap = null,
    multi_map_cldr: ?MultiMap = null,
    single_map: ?SinglesMap = null,
    single_map_cldr: ?SinglesMap = null,
    variable_map: ?AutoHashMap(u32, void) = null,

    fn init(
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

        if (self.ccc_map) |*map| map.deinit();
        if (self.decomp_map) |*map| map.deinit();
        if (self.fcd_map) |*map| map.deinit();
        if (self.multi_map) |*map| map.deinit();
        if (self.multi_map_cldr) |*map| map.deinit();
        if (self.single_map) |*map| map.deinit();
        if (self.single_map_cldr) |*map| map.deinit();
        if (self.variable_map) |*map| map.deinit();
    }

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

        self.a_cea.clearRetainingCapacity();
        self.b_cea.clearRetainingCapacity();

        std.debug.print("a: {any}\n", .{self.a_chars.items});
        std.debug.print("b: {any}\n", .{self.b_chars.items});

        return std.math.order(self.a_chars.items[0], self.b_chars.items[0]);
    }

    pub fn collate(self: *Collator, a: []const u8, b: []const u8) std.math.Order {
        return self.collateFallible(a, b) catch unreachable;
    }

    pub fn getCCC(self: *Collator, codepoint: u32) !?u8 {
        if (self.ccc_map == null) {
            self.ccc_map = try loadCccBin(self.alloc, "bin/ccc.bin");
        }
        return self.ccc_map.?.get(codepoint);
    }

    pub fn getDecomp(self: *Collator, codepoint: u32) !?[]const u32 {
        if (self.decomp_map == null) {
            self.decomp_map = try loadDecompBin(self.alloc, "bin/decomp.bin");
        }
        return self.decomp_map.?.map.get(codepoint);
    }

    pub fn getFCD(self: *Collator, codepoint: u32) !?u16 {
        if (self.fcd_map == null) {
            self.fcd_map = try loadFcdBin(self.alloc, "bin/fcd.bin");
        }
        return self.fcd_map.?.get(codepoint);
    }
};

fn loadCccBin(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 8 * 1024);
    defer alloc.free(data);

    const entry_size = @sizeOf(u32) + @sizeOf(u8);
    const count: u32 = @intCast(data.len / entry_size);

    var map = std.AutoHashMap(u32, u8).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    for (0..count) |i| {
        const offset = i * entry_size;

        const key_bytes = data[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);
        const value = data[offset + @sizeOf(u32)];

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

fn loadDecompBin(alloc: std.mem.Allocator, path: []const u8) !SinglesMap {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 32 * 1024);
    defer alloc.free(data);

    // Map header
    const count = std.mem.readInt(u32, data[0..@sizeOf(u32)], .little);
    const payload = data[@sizeOf(u32)..];

    const entry_header_size = @sizeOf(u32) + @sizeOf(u8);
    const val_count = (payload.len - (count * entry_header_size)) / @sizeOf(u32);

    const vals = try alloc.alloc(u32, val_count);
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    var vals_offset: usize = 0;
    var n: u32 = 0;

    while (n < count) : (n += 1) {
        // Entry header: key
        const key_bytes = payload[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);
        offset += @sizeOf(u32);

        // Entry header: length
        const len = payload[offset];
        offset += @sizeOf(u8);

        // Entry values
        const val_bytes = len * @sizeOf(u32);
        const entry_vals = vals[vals_offset .. vals_offset + len];
        vals_offset += len;

        const payload_vals = std.mem.bytesAsSlice(u32, payload[offset..][0..val_bytes]);
        for (payload_vals, entry_vals) |src, *dst| {
            dst.* = std.mem.littleToNative(u32, src);
        }

        map.putAssumeCapacityNoClobber(key, entry_vals);
        offset += val_bytes;
    }

    return SinglesMap{
        .map = map,
        .backing = vals,
        .alloc = alloc,
    };
}

fn loadFcdBin(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u16) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 8 * 1024);
    defer alloc.free(data);

    const entry_size = @sizeOf(u32) + @sizeOf(u16);
    const count: u32 = @intCast(data.len / entry_size);

    var map = std.AutoHashMap(u32, u16).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    while (offset < data.len) : (offset += entry_size) {
        const key_bytes = data[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);

        const value_bytes = data[offset + @sizeOf(u32) ..][0..@sizeOf(u16)];
        const value = std.mem.readInt(u16, value_bytes, .little);

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

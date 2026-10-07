// Shared with uca-maps-zig/src/collation_table.zig. See that repo's README
// for the LCT1 format and regeneration commands.
const std = @import("std");

pub const Meta = struct {
    first_edge: u32,
    edge_len: u16,
    max_len: u8,
};

pub const Edge = struct {
    codepoint: u32,
    next_first_edge: u32,
    weight_start: u32,
    next_edge_len: u16,
    weight_len: u16,
};

pub const Table = struct {
    page_index: []u16,
    entries: []u64,
    meta: []Meta,
    edges: []Edge,
    weights: []u32,

    // Input is trusted generator output. Integer fields are serialized explicitly
    // in little-endian order, independently of native alignment and struct padding.
    pub fn load(alloc: std.mem.Allocator, data: []const u8) error{ InvalidData, OutOfMemory }!Table {
        if (data.len < 24 or !std.mem.eql(u8, data[0..4], "LCT1")) return error.InvalidData;
        var reader = Reader{ .data = data, .offset = 4 };
        var counts: [5]usize = undefined;
        for (&counts) |*count| count.* = reader.int(u32);
        var size: u64 = 24;
        for (counts, [_]u8{ 2, 8, 7, 16, 4 }) |count, width|
            size += @as(u64, count) * width;
        if (counts[0] != 0x1100 or size != data.len) return error.InvalidData;

        const pages = try alloc.alloc(u16, counts[0]);
        errdefer alloc.free(pages);
        const entries = try alloc.alloc(u64, counts[1]);
        errdefer alloc.free(entries);
        const meta = try alloc.alloc(Meta, counts[2]);
        errdefer alloc.free(meta);
        const edges = try alloc.alloc(Edge, counts[3]);
        errdefer alloc.free(edges);
        const weights = try alloc.alloc(u32, counts[4]);
        errdefer alloc.free(weights);

        for (pages) |*value| value.* = reader.int(u16);
        for (entries) |*value| value.* = reader.int(u64);
        for (meta) |*value| value.* = .{
            .first_edge = reader.int(u32),
            .edge_len = reader.int(u16),
            .max_len = reader.int(u8),
        };
        for (edges) |*value| value.* = .{
            .codepoint = reader.int(u32),
            .next_first_edge = reader.int(u32),
            .weight_start = reader.int(u32),
            .next_edge_len = reader.int(u16),
            .weight_len = reader.int(u16),
        };
        for (weights) |*value| value.* = reader.int(u32);
        return .{ .page_index = pages, .entries = entries, .meta = meta, .edges = edges, .weights = weights };
    }

    pub fn deinit(self: *Table, alloc: std.mem.Allocator) void {
        alloc.free(self.page_index);
        alloc.free(self.entries);
        alloc.free(self.meta);
        alloc.free(self.edges);
        alloc.free(self.weights);
        self.* = undefined;
    }

    pub fn entry(self: *const Table, codepoint: u32) u64 {
        const page: usize = self.page_index[codepoint >> 8];
        return self.entries[(page << 8) + (codepoint & 0xFF)];
    }

    pub fn maxLen(self: *const Table, value: u64) usize {
        return if (isContraction(value)) self.meta[@intCast(value >> 50)].max_len else 1;
    }

    pub fn simpleRow(self: *const Table, value: u64) ?[]const u32 {
        if (value == 0) return null;
        return self.row(@truncate(value >> 18), @truncate(value >> 2));
    }

    pub fn get2(self: *const Table, value: u64, b: u32) ?[]const u32 {
        if (!isContraction(value)) return null;
        const meta = self.meta[@intCast(value >> 50)];
        const edge = self.findEdge(meta.first_edge, meta.edge_len, b) orelse return null;
        return self.row(edge.weight_start, edge.weight_len);
    }

    pub fn get3(self: *const Table, value: u64, b: u32, c: u32) ?[]const u32 {
        if (!isContraction(value)) return null;
        const meta = self.meta[@intCast(value >> 50)];
        const second = self.findEdge(meta.first_edge, meta.edge_len, b) orelse return null;
        const third = self.findEdge(second.next_first_edge, second.next_edge_len, c) orelse return null;
        return self.row(third.weight_start, third.weight_len);
    }

    fn row(self: *const Table, start: u32, len: u16) ?[]const u32 {
        if (len == 0) return null;
        const offset: usize = start;
        return self.weights[offset .. offset + len];
    }

    pub fn contractionRow(self: *const Table, value: u64, suffix: []const u32) ?[]const u32 {
        return switch (suffix.len) {
            1 => self.get2(value, suffix[0]),
            2 => self.get3(value, suffix[0], suffix[1]),
            else => unreachable,
        };
    }

    fn findEdge(self: *const Table, start: u32, len: u16, codepoint: u32) ?Edge {
        const offset: usize = start;
        const edges = self.edges[offset .. offset + len];
        if (len <= 4) {
            for (edges) |edge| {
                if (edge.codepoint == codepoint) return edge;
            }
            return null;
        }

        var low: usize = 0;
        var high = edges.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            if (edges[mid].codepoint < codepoint) {
                low = mid + 1;
            } else if (edges[mid].codepoint > codepoint) {
                high = mid;
            } else return edges[mid];
        }
        return null;
    }
};

fn isContraction(value: u64) bool {
    return value & 3 == 2;
}

const Reader = struct {
    data: []const u8,
    offset: usize,

    fn int(self: *Reader, comptime T: type) T {
        const value = std.mem.readInt(T, self.data[self.offset..][0..@sizeOf(T)], .little);
        self.offset += @sizeOf(T);
        return value;
    }
};

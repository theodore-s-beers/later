const std = @import("std");

const types = @import("types");

pub fn loadCCC(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
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

pub fn loadDecomp(alloc: std.mem.Allocator, path: []const u8) !types.SinglesMap {
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

    return types.SinglesMap{
        .map = map,
        .backing = vals,
        .alloc = alloc,
    };
}

pub fn loadFCD(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u16) {
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

pub fn loadVariable(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, void) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024);
    defer alloc.free(data);

    const count: usize = data.len / @sizeOf(u32);

    var map = std.AutoHashMap(u32, void).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(@intCast(count));

    for (0..count) |i| {
        const offset = i * @sizeOf(u32);

        const bytes = data[offset..][0..@sizeOf(u32)];
        const code_point = std.mem.readInt(u32, bytes, .little);

        map.putAssumeCapacityNoClobber(code_point, {});
    }

    return map;
}

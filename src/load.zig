const std = @import("std");
const types = @import("types");

const decomp_data = @embedFile("bin/decomp.bin");
const fcd_data = @embedFile("bin/fcd.bin");
const multi_data = @embedFile("bin/multi.bin");
const multi_cldr_data = @embedFile("bin/multi_cldr.bin");
const singles_data = @embedFile("bin/singles.bin");
const singles_cldr_data = @embedFile("bin/singles_cldr.bin");
const variable_data = @embedFile("bin/variable.bin");

pub fn loadDecomp(alloc: std.mem.Allocator) types.SinglesMap {
    // Map header
    const count = std.mem.readInt(u32, decomp_data[0..@sizeOf(u32)], .little);
    const payload = decomp_data[@sizeOf(u32)..];

    const entry_header_size = @sizeOf(u32) + @sizeOf(u8);
    const val_count = (payload.len - (count * entry_header_size)) / @sizeOf(u32);

    const vals = alloc.alloc(u32, val_count) catch @panic("OOM in Collator");
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer map.deinit();

    map.ensureTotalCapacity(count) catch @panic("OOM in Collator");

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

pub fn loadFCD(alloc: std.mem.Allocator) std.AutoHashMap(u32, u16) {
    const entry_size = @sizeOf(u32) + @sizeOf(u16);
    const count: u32 = @intCast(fcd_data.len / entry_size);

    var map = std.AutoHashMap(u32, u16).init(alloc);
    errdefer map.deinit();

    map.ensureTotalCapacity(count) catch @panic("OOM in Collator");

    var offset: usize = 0;
    while (offset < fcd_data.len) : (offset += entry_size) {
        const key_bytes = fcd_data[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);

        const value_bytes = fcd_data[offset + @sizeOf(u32) ..][0..@sizeOf(u16)];
        const value = std.mem.readInt(u16, value_bytes, .little);

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

pub fn loadMulti(alloc: std.mem.Allocator, cldr: bool) types.MultiMap {
    const data = if (cldr) multi_cldr_data else multi_data;

    // Map header
    const count = std.mem.readInt(u16, data[0..@sizeOf(u16)], .little);
    const payload = data[@sizeOf(u16)..];

    const entry_header_size = @sizeOf(u64) + @sizeOf(u8);
    const val_count = (payload.len - (count * entry_header_size)) / @sizeOf(u32);

    const vals = alloc.alloc(u32, val_count) catch @panic("OOM in Collator");
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u64, []const u32).init(alloc);
    errdefer map.deinit();

    map.ensureTotalCapacity(count) catch @panic("OOM in Collator");

    var offset: usize = 0;
    var vals_offset: usize = 0;
    var n: u16 = 0;

    while (n < count) : (n += 1) {
        // Entry header: key
        const key_bytes = payload[offset..][0..@sizeOf(u64)];
        const key = std.mem.readInt(u64, key_bytes, .little);
        offset += @sizeOf(u64);

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

    return types.MultiMap{
        .map = map,
        .backing = vals,
        .alloc = alloc,
    };
}

pub fn loadSingle(alloc: std.mem.Allocator, cldr: bool) types.SinglesMap {
    const data = if (cldr) singles_cldr_data else singles_data;

    const count = std.mem.readInt(u32, data[0..@sizeOf(u32)], .little); // Map header
    const payload = data[@sizeOf(u32)..];

    const entry_header_size = @sizeOf(u32) + @sizeOf(u8);
    const val_count = (payload.len - (count * entry_header_size)) / @sizeOf(u32);

    const vals = alloc.alloc(u32, val_count) catch @panic("OOM in Collator");
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer map.deinit();

    map.ensureTotalCapacity(count) catch @panic("OOM in Collator");

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

pub fn loadVariable(alloc: std.mem.Allocator) std.AutoHashMap(u32, void) {
    const count: usize = variable_data.len / @sizeOf(u32);

    var map = std.AutoHashMap(u32, void).init(alloc);
    errdefer map.deinit();

    map.ensureTotalCapacity(@intCast(count)) catch @panic("OOM in Collator");

    for (0..count) |i| {
        const offset = i * @sizeOf(u32);

        const bytes = variable_data[offset..][0..@sizeOf(u32)];
        const code_point = std.mem.readInt(u32, bytes, .little);

        map.putAssumeCapacityNoClobber(code_point, {});
    }

    return map;
}

const std = @import("std");
const testing = std.testing;

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

        const a_codepoints = try bytesToCodepoints(self.alloc, a);
        defer self.alloc.free(a_codepoints);

        const b_codepoints = try bytesToCodepoints(self.alloc, b);
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

pub fn bytesToCodepoints(alloc: std.mem.Allocator, input: []const u8) ![]u32 {
    var codepoints = try std.ArrayList(u32).initCapacity(alloc, input.len);
    errdefer codepoints.deinit();

    var state: u8 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    for (input) |b| {
        const new_state = decode(&state, &codepoint, b);

        if (new_state == UTF8_REJECT) {
            codepoints.appendAssumeCapacity(REPLACEMENT);
            state = UTF8_ACCEPT;
        } else if (new_state == UTF8_ACCEPT) {
            codepoints.appendAssumeCapacity(codepoint);
        }
    }

    // If we ended in an incomplete sequence, emit replacement
    if (state != UTF8_ACCEPT) {
        codepoints.appendAssumeCapacity(REPLACEMENT);
    }

    return codepoints.toOwnedSlice();
}

const UTF8_ACCEPT: u8 = 0;
const UTF8_REJECT: u8 = 12;

const REPLACEMENT: u32 = 0xFFFD;

const utf8d = [_]u8{
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,
    7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,
    8,  8,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,
    10, 3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  4,  3,  3,  11, 6,  6,  6,  5,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,

    0,  12, 24, 36, 60, 96, 84, 12, 12, 12, 48, 72, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 0,  12, 12, 12, 12, 12, 0,
    12, 0,  12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 24, 12, 12, 12, 12, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 12,
    12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12, 12, 36, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12,
    12, 36, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
};

inline fn decode(state: *u8, cp: *u32, byte: u8) u8 {
    const class = utf8d[byte];

    cp.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3F) | (cp.* << 6)
    else
        ((@as(u8, 0xFF) >> @truncate(class)) & byte);

    const idx = @as(usize, 256) + state.* + class;
    state.* = utf8d[idx];

    return state.*;
}

test "collation of identical strings" {
    const allocator = std.testing.allocator;
    var collator = Collator.initDefault(allocator);
    defer collator.deinit();

    const a = "مصطفى";
    const b = "مصطفى";

    try testing.expect(collator.collate(a, b));
}

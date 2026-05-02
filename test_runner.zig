const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) void {
    const io = init.io;

    if (builtin.test_functions.len == 0) return;

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    for (builtin.test_functions) |t| {
        std.testing.allocator_instance = .{};

        const start = std.Io.Clock.Timestamp.now(io, .awake);
        const result = t.func();
        const end = std.Io.Clock.Timestamp.now(io, .awake);

        const ns: u64 = @intCast(start.durationTo(end).raw.nanoseconds);
        const ms = @as(f64, @floatFromInt(ns)) / 1_000_000.0;

        var status: enum { pass, fail, skip } = .pass;

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                status = .skip;
            },
            else => {
                fail += 1;
                status = .fail;

                std.debug.print("\nFAIL: {s}: {s}\n", .{ t.name, @errorName(err) });

                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpErrorReturnTrace(trace);
                }
            },
        }

        var leaked = false;

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            leaked = true;
            status = .fail;
            std.debug.print("\nLEAK: {s}\n", .{t.name});
        }

        const status_str = switch (status) {
            .pass => "OK",
            .fail => if (leaked) "FAIL (LEAK)" else "FAIL",
            .skip => "SKIP",
        };

        std.debug.print("{s} ... {s} ({d:.2}ms)\n", .{ t.name, status_str, ms });
    }

    std.debug.print(
        "==> {d} passed, {d} failed, {d} skipped, {d} leaked\n\n",
        .{ pass, fail, skip, leak },
    );

    std.process.exit(if (fail == 0 and leak == 0) 0 else 1);
}

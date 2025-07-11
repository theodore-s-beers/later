const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("later", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ascii_mod = b.createModule(.{
        .root_source_file = b.path("src/ascii.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cea_mod = b.createModule(.{
        .root_source_file = b.path("src/cea.zig"),
        .target = target,
        .optimize = optimize,
    });

    const collator_mod = b.createModule(.{
        .root_source_file = b.path("src/collator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const consts_mod = b.createModule(.{
        .root_source_file = b.path("src/consts.zig"),
        .target = target,
        .optimize = optimize,
    });

    const decode_mod = b.createModule(.{
        .root_source_file = b.path("src/decode.zig"),
        .target = target,
        .optimize = optimize,
    });

    const load_mod = b.createModule(.{
        .root_source_file = b.path("src/load.zig"),
        .target = target,
        .optimize = optimize,
    });

    const normalize_mod = b.createModule(.{
        .root_source_file = b.path("src/normalize.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sort_key_mod = b.createModule(.{
        .root_source_file = b.path("src/sort_key.zig"),
        .target = target,
        .optimize = optimize,
    });

    const types_mod = b.createModule(.{
        .root_source_file = b.path("src/types.zig"),
        .target = target,
        .optimize = optimize,
    });

    const util_mod = b.createModule(.{
        .root_source_file = b.path("src/util.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("collator", collator_mod);

    ascii_mod.addImport("util", util_mod);

    cea_mod.addImport("collator", collator_mod);
    cea_mod.addImport("consts", consts_mod);
    cea_mod.addImport("util", util_mod);

    collator_mod.addImport("ascii", ascii_mod);
    collator_mod.addImport("cea", cea_mod);
    collator_mod.addImport("consts", consts_mod);
    collator_mod.addImport("decode", decode_mod);
    collator_mod.addImport("load", load_mod);
    collator_mod.addImport("normalize", normalize_mod);
    collator_mod.addImport("sort_key", sort_key_mod);
    collator_mod.addImport("types", types_mod);
    collator_mod.addImport("util", util_mod);

    load_mod.addImport("types", types_mod);

    normalize_mod.addImport("collator", collator_mod);

    sort_key_mod.addImport("util", util_mod);

    util_mod.addImport("collator", collator_mod);
    util_mod.addImport("consts", consts_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "later",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{ .root_module = lib_mod });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const ascii_unit_tests = b.addTest(.{ .root_module = ascii_mod });
    const run_ascii_unit_tests = b.addRunArtifact(ascii_unit_tests);

    const cea_unit_tests = b.addTest(.{ .root_module = cea_mod });
    const run_cea_unit_tests = b.addRunArtifact(cea_unit_tests);

    const collator_unit_tests = b.addTest(.{ .root_module = collator_mod });
    const run_collator_unit_tests = b.addRunArtifact(collator_unit_tests);

    const consts_unit_tests = b.addTest(.{ .root_module = consts_mod });
    const run_consts_unit_tests = b.addRunArtifact(consts_unit_tests);

    const decode_unit_tests = b.addTest(.{ .root_module = decode_mod });
    const run_decode_unit_tests = b.addRunArtifact(decode_unit_tests);

    const load_unit_tests = b.addTest(.{ .root_module = load_mod });
    const run_load_unit_tests = b.addRunArtifact(load_unit_tests);

    const normalize_unit_tests = b.addTest(.{ .root_module = normalize_mod });
    const run_normalize_unit_tests = b.addRunArtifact(normalize_unit_tests);

    const sort_key_unit_tests = b.addTest(.{ .root_module = sort_key_mod });
    const run_sort_key_unit_tests = b.addRunArtifact(sort_key_unit_tests);

    const types_unit_tests = b.addTest(.{ .root_module = types_mod });
    const run_types_unit_tests = b.addRunArtifact(types_unit_tests);

    const util_unit_tests = b.addTest(.{ .root_module = util_mod });
    const run_util_unit_tests = b.addRunArtifact(util_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_ascii_unit_tests.step);
    test_step.dependOn(&run_cea_unit_tests.step);
    test_step.dependOn(&run_collator_unit_tests.step);
    test_step.dependOn(&run_consts_unit_tests.step);
    test_step.dependOn(&run_decode_unit_tests.step);
    test_step.dependOn(&run_load_unit_tests.step);
    test_step.dependOn(&run_normalize_unit_tests.step);
    test_step.dependOn(&run_sort_key_unit_tests.step);
    test_step.dependOn(&run_types_unit_tests.step);
    test_step.dependOn(&run_util_unit_tests.step);
}

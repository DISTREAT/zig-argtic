const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zig-argtic", "src/zig-argtic.zig");
    const lib_tests = b.addTest("src/tests.zig");
    const example = b.addExecutable("example-calculator", "examples/calculator.zig");

    const zig_argtic = std.build.Pkg{ .name = "zig-argtic", .source = .{ .path = "src/zig-argtic.zig" } };
    example.addPackage(zig_argtic);

    lib.setBuildMode(mode);
    lib.setTarget(target);

    lib.emit_docs = .emit;
    lib.install();

    const example_run_step = example.run();
    if (b.args) |args| {
        example_run_step.addArgs(args);
    }

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&lib_tests.step);
    const example_step = b.step("example", "Run an example application");
    example_step.dependOn(&example_run_step.step);
}

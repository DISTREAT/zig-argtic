const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zig-argtic", "src/zig-argtic.zig");
    const lib_tests = b.addTest("src/tests.zig");

    lib.setBuildMode(mode);
    lib.setTarget(target);

    lib.emit_docs = .emit;
    lib.install();

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&lib_tests.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});

    _ = b.addModule("zig-argtic", .{
        .root_source_file = b.path("src/zig-argtic.zig"),
        .optimize = mode,
        .target = target,
    });

    const lib = b.addStaticLibrary(.{
        .name = "zig-argtic",
        .root_source_file = b.path("src/zig-argtic.zig"),
        .optimize = mode,
        .target = target,
    });
    const lib_tests = b.addTest(.{ .root_source_file = b.path("src/tests.zig") });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .{ .custom = ".." },
        .install_subdir = "docs",
    });

    b.installArtifact(lib);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    const docs_step = b.step("docs", "Build the documentation");
    docs_step.dependOn(&install_docs.step);
}

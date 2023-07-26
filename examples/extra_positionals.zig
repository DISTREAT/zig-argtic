//! This module is just a simple example on how to utilize zig-argtic
//!
const std = @import("std");
const argtic = @import("zig-argtic");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    const specification = argtic.ArgumentSpecification{
        .name = "example",
        .short_description = "Just a basic example on how to parse extra arguments",
        .extra_positionals = argtic.Positional{
            .name = "files",
            .help = "The files you would like to work with",
        },
    };

    const argument_vector = try std.process.argsAlloc(allocator);
    defer allocator.free(argument_vector);

    const arguments = argtic.ArgumentProcessor.parse(allocator, specification, argument_vector[1..]) catch |e| return try argtic.defaultErrorHandler(e);
    defer arguments.deinit();

    const files = try arguments.getExtraPositionals(allocator);
    defer allocator.free(files);

    if (files.len == 0) return std.log.err("No files were provided", .{});

    for (files) |file, index| {
        std.log.info("File {d}: {s}", .{ index, file });
    }
}

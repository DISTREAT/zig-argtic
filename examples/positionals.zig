//! This module is just a simple example on how to utilize zig-argtic
//!
const std = @import("std");
const argtic = @import("zig-argtic");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const specification = argtic.ArgumentSpecification{
        .name = "example",
        .short_description = "Just a basic example on how to parse positional arguments",
        .long_description = "This right here is a longer description of your software",
        .positionals = &[_]argtic.Positional{
            .{ .name = "value", .help = "The value you would like to provide" },
        },
    };

    const argument_vector = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argument_vector);

    const arguments = argtic.ArgumentProcessor.parse(allocator, specification, argument_vector[1..]) catch |e| return try argtic.defaultErrorHandler(e);
    defer arguments.deinit();

    std.log.info("Your value: {s}", .{arguments.getArgument("value").?});
}

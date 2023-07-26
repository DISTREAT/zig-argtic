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
        .short_description = "Just a basic example on how to parse optional arguments",
        .flags = &[_]argtic.Flag{
            .{ .name = "help", .short = 'h', .abort = true, .help = "Displays this help message" },
            .{ .name = "version", .help = "Displays the program's version" },
            .{ .name = "name", .short = 'n', .value = true, .help = "Your name" },
        },
    };

    const argument_vector = try std.process.argsAlloc(allocator);
    defer allocator.free(argument_vector);

    const arguments = argtic.ArgumentProcessor.parse(allocator, specification, argument_vector[1..]) catch |e| return try argtic.defaultErrorHandler(e);
    defer arguments.deinit();

    if (arguments.isArgument("name")) {
        const name = arguments.getArgument("name").?;
        std.log.info("Your name is: {s}", .{name});
        return;
    }

    if (arguments.isArgument("version")) std.log.info("0.1.0", .{});
    if (arguments.isArgument("help")) try argtic.generateHelpMessage(arguments.tokenizer.specification);

    try argtic.generateUsageMessage(specification);
}

//! This module is just a simple example on how to utilize zig-argtic
//!
const std = @import("std");
const argtic = @import("zig-argtic");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const flag_help = argtic.Flag{
        .name = "help",
        .short = 'h',
        .abort = true,
        .help = "Displays this help message",
    };

    const specification = argtic.ArgumentSpecification{
        .name = "example",
        .short_description = "Just an example on how to use subcommands",
        .flags = &[_]argtic.Flag{flag_help},
        .subcommands = &[_]argtic.ArgumentSpecification{
            .{
                .name = "add",
                .short_description = "Addition",
                .flags = &[_]argtic.Flag{flag_help},
            },
            .{
                .name = "sub",
                .short_description = "Substraction",
                .flags = &[_]argtic.Flag{flag_help},
            },
        },
    };

    const argument_vector = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argument_vector);

    const arguments = argtic.ArgumentProcessor.parse(allocator, specification, argument_vector[1..]) catch |e| return try argtic.defaultErrorHandler(e);
    defer arguments.deinit();

    if (arguments.isArgument("help")) {
        try argtic.generateHelpMessage(arguments.tokenizer.specification);
    } else if (arguments.isArgument("add")) {
        std.log.info("subcommand add", .{});
    } else if (arguments.isArgument("sub")) {
        std.log.info("subcommand sub", .{});
    } else {
        try argtic.generateUsageMessage(arguments.tokenizer.specification);
    }
}

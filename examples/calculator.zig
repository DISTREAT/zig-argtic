//! This module is just a simple example on how to utilize zig-argtic
//! The code is not very well written, but it should get the idea across
//!
const std = @import("std");
const argtic = @import("zig-argtic");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    const specification = argtic.ArgumentSpecification{
        .name = "calcun",
        .short_description = "calcun - scientific calculator for complex calculations",
        .long_description = 
        \\Introducing CalcUn - the calculator that rewrites history!
        \\With its mind-boggling base1 algorithms and quantum-powered calculations,
        \\it'll solve equations faster than you can say "E=mc²".
        ,
        .flags = &[_]argtic.Flag{
            .{ .name = "help", .short = 'h', .help = "Show this help message", .abort = true },
            .{ .name = "version", .value = true, .help = "Will print out the version you provide" },
        },
        .subcommands = &[_]argtic.ArgumentSpecification{
            .{
                .name = "add",
                .short_description = "Calculate additions",
                .extra_positionals = argtic.Positional{ .name = "numbers", .help = "The numbers to add together" },
                .flags = &[_]argtic.Flag{.{ .name = "help", .short = 'h', .help = "Show this help message", .abort = true }},
            },
            .{
                .name = "sub",
                .short_description = "Calculate substractions",
                .positionals = &[_]argtic.Positional{
                    .{ .name = "first number" },
                    .{ .name = "second number" },
                },
                .flags = &[_]argtic.Flag{.{ .name = "help", .short = 'h', .help = "Show this help message", .abort = true }},
            },
        },
    };

    const argument_vector = try std.process.argsAlloc(allocator);
    defer allocator.free(argument_vector);

    const arguments = argtic.ArgumentProcessor.parse(allocator, specification, argument_vector[1..]) catch |e| return try argtic.defaultErrorHandler(e);
    defer arguments.deinit();

    if (arguments.isArgument("help")) {
        try argtic.generateHelpMessage(arguments.tokenizer.specification);
    } else if (arguments.isArgument("version")) {
        try stdout.print("{s}\n", .{arguments.getArgument("version").?});
    } else if (arguments.isArgument("add")) {
        const numbers = try arguments.getExtraPositionals(allocator);
        defer allocator.free(numbers);

        var sum: u32 = 0;

        for (numbers) |ascii_number, argument_index| {
            const number = std.fmt.parseInt(u32, ascii_number, 0) catch return try stdout.writeAll("I don't understand these numbers yet :(");

            // print stupid base1 bs
            var index: usize = 0;
            while (index < number) : (index += 1) {
                if (index != 0 or argument_index != 0) try stdout.writeAll(" + ");
                try stdout.writeAll("1");
            }

            sum += number;
        }

        try stdout.print(" = {d}\n", .{sum});
    } else if (arguments.isArgument("sub")) {
        const number_1 = std.fmt.parseInt(i32, arguments.getArgument("first number").?, 0) catch {
            return try stdout.writeAll("I don't understand these numbers yet :(");
        };
        const number_2 = std.fmt.parseInt(i32, arguments.getArgument("second number").?, 0) catch {
            return try stdout.writeAll("I don't understand these numbers yet :(");
        };

        try stdout.writeAll("Note to myself: Implement base1 algorithm\n");
        try stdout.print("{d} - {d} = {d}\n", .{ number_1, number_2, number_1 - number_2 });
    } else {
        try argtic.generateUsageMessage(specification);
    }

    return;
}

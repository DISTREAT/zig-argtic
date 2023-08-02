//! Unit and Integration tests for the module scope `src/*.zig`
//! [Released under GNU LGPLv3
//
// The provided integration test cases are not assumed to be very extensive
//
const std = @import("std");
const argtic = @import("zig-argtic.zig");
const expect = std.testing.expect;
const allocator = std.testing.allocator;

test "Parsing positional arguments" {
    const specification = argtic.ArgumentSpecification{
        .name = "Test App",
        .positionals = &[_]argtic.Positional{
            .{ .name = "name" },
            .{ .name = "nick" },
        },
    };

    const arguments_case_1 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "Nick", "Nik" });
    defer arguments_case_1.deinit();

    // invalid argument cases
    const arguments_case_2 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "Nick", "Nik", "Too Many Pos" });
    try expect(arguments_case_2 == error.AssumptionTooManyPositionals);

    const arguments_case_3 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{"Nick"});
    try expect(arguments_case_3 == error.MissingPositionals);

    const arguments_case_4 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{});
    try expect(arguments_case_4 == error.MissingPositionals);

    // lower-level tests
    try expect(arguments_case_1.tokens.len == 2);
    for (arguments_case_1.tokens) |token| try expect(token == .positional);

    // higher-level tests
    try expect(arguments_case_1.isArgument("name"));
    try expect(arguments_case_1.isArgument("nick"));
    try expect(std.mem.eql(u8, arguments_case_1.getArgument("name").?, "Nick"));
    try expect(std.mem.eql(u8, arguments_case_1.getArgument("nick").?, "Nik"));

    // misc tests
    try expect(!arguments_case_1.isArgument("non-existent"));
    try expect(arguments_case_1.getArgument("non-existent") == null);
}

test "Parsing flags alongside positional arguments" {
    const specification = argtic.ArgumentSpecification{
        .name = "Test App",
        .flags = &[_]argtic.Flag{
            .{ .name = "help", .short = 'h', .abort = true },
            .{ .name = "test" },
            .{ .name = "log-level", .value = true },
        },
        .positionals = &[_]argtic.Positional{
            .{ .name = "Nickname" },
        },
    };

    const arguments_case_1 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{"--help"});
    defer arguments_case_1.deinit();

    const arguments_case_2 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{"-h"});
    defer arguments_case_2.deinit();

    const arguments_case_3 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--log-level=2", "Nik" });
    defer arguments_case_3.deinit();

    const arguments_case_4 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--log-level", "3", "Nik" });
    defer arguments_case_4.deinit();

    const arguments_case_5 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "Nik", "--log-level=3" });
    defer arguments_case_5.deinit();

    // invalid argument cases
    const arguments_case_6 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--non-existant", "Nik" });
    try expect(arguments_case_6 == error.FlagNotFound);

    const arguments_case_7 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--non-existant=50", "Nik" });
    try expect(arguments_case_7 == error.FlagNotFound);

    const arguments_case_8 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-n", "Nik" });
    try expect(arguments_case_8 == error.FlagNotFound);

    const arguments_case_9 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--help=1", "Nik" });
    try expect(arguments_case_9 == error.ValueNotExpected);

    const arguments_case_10 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--test", "1", "Nik" });
    try expect(arguments_case_10 == error.AssumptionTooManyPositionals);

    // higher-level tests
    try expect(arguments_case_1.isArgument("help"));
    try expect(!arguments_case_1.isArgument("Nickname"));

    try expect(arguments_case_2.isArgument("help"));

    try expect(arguments_case_3.isArgument("log-level"));
    try expect(arguments_case_3.isArgument("Nickname"));
    try expect(std.mem.eql(u8, arguments_case_3.getArgument("log-level").?, "2"));

    try expect(arguments_case_4.isArgument("log-level"));
    try expect(arguments_case_4.isArgument("Nickname"));
    try expect(std.mem.eql(u8, arguments_case_4.getArgument("log-level").?, "3"));

    try expect(arguments_case_5.isArgument("log-level"));
    try expect(arguments_case_5.isArgument("Nickname"));
    try expect(std.mem.eql(u8, arguments_case_5.getArgument("log-level").?, "3"));
}

test "Parsing multiple flag values" {
    const specification = argtic.ArgumentSpecification{
        .name = "Test App",
        .flags = &[_]argtic.Flag{
            .{ .name = "exclude", .short = 'e', .value = true },
        },
    };

    const arguments_case_1 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-e", "a", "--exclude=b", "--exclude", "c" });
    defer arguments_case_1.deinit();

    const arguments_case_2 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-e", "test" });
    defer arguments_case_2.deinit();

    const arguments_case_1_values = (try arguments_case_1.getArguments(allocator, "exclude")).?;
    defer allocator.free(arguments_case_1_values);

    const arguments_case_2_values = (try arguments_case_2.getArguments(allocator, "exclude")).?;
    defer allocator.free(arguments_case_2_values);

    try expect(arguments_case_1_values.len == 3);
    try expect(arguments_case_1_values[0][0] == 'a');
    try expect(arguments_case_1_values[1][0] == 'b');
    try expect(arguments_case_1_values[2][0] == 'c');

    try expect(arguments_case_2_values.len == 1);
    try expect(std.mem.eql(u8, arguments_case_2_values[0], "test"));
    try expect(std.mem.eql(u8, arguments_case_2.getArgument("exclude").?, "test"));
}

test "Parsing flags utilizing the compound-flag syntax" {
    const specification = argtic.ArgumentSpecification{
        .name = "Test App",
        .flags = &[_]argtic.Flag{
            .{ .name = "help", .short = 'h' },
            .{ .name = "version", .short = 'v' },
            .{ .name = "log", .short = 'l' },
            .{ .name = "test", .short = 't', .value = true },
        },
        .positionals = &[_]argtic.Positional{
            .{ .name = "Nickname" },
        },
    };

    const arguments_case_1 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-vl", "Nik" });
    defer arguments_case_1.deinit();

    const arguments_case_2 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-lh", "Nik" });
    defer arguments_case_2.deinit();

    // invalid argument cases
    const arguments_case_3 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "--hv", "Nik" });
    try expect(arguments_case_3 == error.FlagNotFound);

    const arguments_case_4 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-test", "Nik" });
    try expect(arguments_case_4 == error.FlagNotFound);

    const arguments_case_5 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "-ht", "val", "Nik" });
    try expect(arguments_case_5 == error.AssumptionTooManyPositionals);

    // higher-level tests
    try expect(!arguments_case_1.isArgument("help"));
    try expect(arguments_case_1.isArgument("version"));
    try expect(arguments_case_1.isArgument("log"));

    try expect(arguments_case_2.isArgument("help"));
    try expect(!arguments_case_2.isArgument("version"));
    try expect(arguments_case_2.isArgument("log"));
}

test "Parsing extra positional arguments, with and without positional arguments" {
    const specification = argtic.ArgumentSpecification{
        .name = "Test App",
        .positionals = &[_]argtic.Positional{
            .{ .name = "target" },
        },
        .extra_positionals = argtic.Positional{
            .name = "files",
        },
    };

    const arguments_case_1 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "host1", "file1.txt", "file2.txt" });
    defer arguments_case_1.deinit();

    const arguments_case_2 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{"host1"});
    defer arguments_case_2.deinit();

    // higher-level tests
    try expect(arguments_case_1.isArgument("target"));
    try expect(arguments_case_1.isArgument("files"));
    try expect(std.mem.eql(u8, arguments_case_1.getArgument("target").?, "host1"));

    const files = try arguments_case_1.getExtraPositionals(allocator);
    defer allocator.free(files);

    try expect(files.len == 2);
    try expect(std.mem.eql(u8, files[0], "file1.txt"));
    try expect(std.mem.eql(u8, files[1], "file2.txt"));

    try expect(arguments_case_2.isArgument("target"));
    try expect(!arguments_case_2.isArgument("files"));
    try expect(std.mem.eql(u8, arguments_case_2.getArgument("target").?, "host1"));
}

test "Parsing positional arguments utilizing sub-commands" {
    const specification = argtic.ArgumentSpecification{
        .name = "Command",
        .positionals = &[_]argtic.Positional{
            .{ .name = "com" },
        },
        .subcommands = &[_]argtic.ArgumentSpecification{
            .{
                .name = "sub-b",
                .positionals = &[_]argtic.Positional{
                    .{ .name = "b" },
                },
            },
            .{
                .name = "sub-c",
                .positionals = &[_]argtic.Positional{
                    .{ .name = "c" },
                },
            },
        },
    };

    const arguments_case_1 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{"com"});
    defer arguments_case_1.deinit();

    const arguments_case_2 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "sub-b", "b" });
    defer arguments_case_2.deinit();

    const arguments_case_3 = try argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{ "sub-c", "c" });
    defer arguments_case_3.deinit();

    // invalid argument cases
    const arguments_case_4 = argtic.ArgumentProcessor.parse(allocator, specification, &[_][]const u8{});
    try expect(arguments_case_4 == error.MissingPositionals);

    // lower-level tests
    try expect(arguments_case_1.tokens.len == 1);
    try expect(arguments_case_1.tokens[0] == .positional);

    try expect(arguments_case_2.tokens.len == 2);
    try expect(arguments_case_2.tokens[0] == .subcommand);
    try expect(arguments_case_2.tokens[1] == .positional);

    try expect(arguments_case_3.tokens.len == 2);
    try expect(arguments_case_3.tokens[0] == .subcommand);
    try expect(arguments_case_3.tokens[1] == .positional);

    // higher-level tests
    try expect(!arguments_case_1.isArgument("sub-b"));
    try expect(!arguments_case_1.isArgument("sub-c"));
    try expect(arguments_case_1.isArgument("com"));
    try expect(std.mem.eql(u8, arguments_case_1.getArgument("com").?, "com"));

    try expect(arguments_case_2.isArgument("sub-b"));
    try expect(!arguments_case_2.isArgument("sub-c"));
    try expect(arguments_case_2.isArgument("b"));
    try expect(std.mem.eql(u8, arguments_case_2.getArgument("b").?, "b"));

    try expect(!arguments_case_3.isArgument("sub-b"));
    try expect(arguments_case_3.isArgument("sub-c"));
    try expect(arguments_case_3.isArgument("c"));
    try expect(std.mem.eql(u8, arguments_case_3.getArgument("c").?, "c"));
}

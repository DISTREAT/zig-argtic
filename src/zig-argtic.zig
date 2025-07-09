//! This module provides structs for parsing command-line options, arguments, and subcommands
//! [Released under GNU LGPLv3]
//!
//! zig-autodoc-guide: ../../README.md
//! zig-autodoc-guide: ../../LICENSE.txt
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// Representation of an optional argument
pub const Flag = struct {
    /// The unique identifier of the optional argument
    name: []const u8,
    /// An unique abbreviation for the optional argument
    short: ?u8 = null,
    /// Whether the argument should be able to hold any values
    value: bool = false,
    /// Abort the parsing process as soon as this option has passed lexical analysis
    abort: bool = false,
    /// A brief description of the argument
    help: ?[]const u8 = null,
};

/// Representation of a required argument
pub const Positional = struct {
    /// The unique identifier of the required argument
    name: []const u8,
    /// A brief description of the argument
    help: ?[]const u8 = null,
};

/// A struct for defining how and what arguments your program should be able to parse
pub const ArgumentSpecification = struct {
    /// The name of your program (or unique name of the subcommand when passed as a subcommand)
    name: []const u8,
    /// A brief description of your program
    short_description: ?[]const u8 = null,
    /// A more detailed description of your program and/or additional information
    long_description: ?[]const u8 = null,
    /// Arguments that are not required
    flags: []const Flag = &.{},
    /// Arguments that are required and have distinct identifiers for each index
    positionals: []const Positional = &.{},
    /// A special positional argument that acts as a placeholder for all additional arguments
    /// not defined under the regular positionals (ex. could take a list of files)
    extra_positionals: ?Positional = null,
    /// Arguments that refer to other ArgumentSpecifications when called, grouping different actions
    subcommands: []const ArgumentSpecification = &.{},
};

/// Errors produced, calling a method of struct ArgumentTokenizer that returns in a failure to tokenize the input
pub const ArgumentTokenizerError = error{
    /// The argument vector is missing positional arguments
    MissingPositionals,
    /// The provided flag name does not exist within the focused specification
    FlagNotFound,
    /// The provided flag requires a value, but no value was provided
    NoValueProvided,
    /// The provided flag could not be split into value and identifier
    SplitFlagValue,
    /// The provided arguments could not be parsed, presumably because too many positionals were provided
    AssumptionTooManyPositionals,
    /// The gnu optional=value syntax was not respected, because there are too many equal signs
    TooManyEqualSigns,
    /// The flag does not accept any values
    ValueNotExpected,
    /// There is not enough memory to tokenize the input
    OutOfMemory,
};

// A struct for the tokenization of command-line arguments for further processing
// Note: Due to the complexity of this task the differentiation between lexing and parsing
//       is not made and summarized as tokenization
pub const ArgumentTokenizer = struct {
    /// Storing the index of the argument in ArgumentTokenizer.argument_vector that will be focus next by ArgumentTokenizer.nextToken
    argument_index: usize = 0,
    /// Storing the index that will be assigned to the next Positional lexed
    positional_index: usize = 0,
    /// Abort the lexing process, will cause ArgumentTokenizer.nextToken to return null in any case without final checks (used for Flag.abort)
    abort_lexing: bool = false,
    /// An allocator used for buffering purposes (and provisional as an allocator for compound_flag tokens)
    allocator: Allocator,
    /// The argument specification that should be used to understand and tokenize the ArgumentTokenizer.argument_vector
    specification: ArgumentSpecification,
    /// A slice containing all the arguments for the tokenization process
    argument_vector: []const []const u8,

    /// A union representing the tokens of the 'lexical analysis'
    pub const Token = union(enum) {
        flag: struct {
            name: []const u8,
            value: ?[]const u8 = null,
        },
        compound_flag: struct {
            /// A slice of all the flag names passed
            /// Note: compound flags may not have any value
            flags: []const []const u8,
            /// Allocator for the allocation of flag names
            allocator: Allocator,

            // Not a fan of this solution, but better than having a segmentation fault ;)
            // I should rework the memory management asap
            pub fn deinit(self: @This()) void {
                self.allocator.free(self.flags);
            }
        },
        subcommand: struct {
            name: []const u8,
            /// The ArgumentSpecification of the subcommand
            specification: ArgumentSpecification,
        },
        positional: struct {
            name: []const u8,
            value: []const u8,
        },
        extra_positional: struct {
            name: []const u8,
            value: []const u8,
        },
    };

    /// The order of the lexing methods that will be used for the tokenization process
    const lexing_functions = [_]*const fn (*ArgumentTokenizer) ArgumentTokenizerError!?Token{
        // oder matters, since it will define control flow
        &lexCompoundFlag,
        &lexFlag,
        &lexSubcommand,
        &lexPositional,
        &lexExtraPositionals,
    };

    /// Convenience method for returning the flag with the provided name
    fn getFlagLong(self: ArgumentTokenizer, searched_flag_name: []const u8) ?Flag {
        for (self.specification.flags) |flag| {
            if (std.mem.eql(u8, flag.name, searched_flag_name)) return flag;
        }
        return null;
    }

    /// Convenience method for returning the flag with the provided shorthand
    fn getFlagShort(self: ArgumentTokenizer, searched_flag_shorthand: u8) ?Flag {
        for (self.specification.flags) |flag| {
            if (flag.short == null) continue;
            if (flag.short.? == searched_flag_shorthand) return flag;
        }
        return null;
    }

    /// When the method ArgumentTokenizer.nextToken returns null, indicating that the last Token has passed,
    /// this method will be run to provide some more idiot-proofing checks (to Fail-Fast)
    fn finalChecks(self: ArgumentTokenizer) ArgumentTokenizerError!void {
        if (self.positional_index < self.specification.positionals.len) return error.MissingPositionals;
    }

    /// Lex for short and long flags with or without value
    fn lexFlag(self: *ArgumentTokenizer) ArgumentTokenizerError!?Token {
        // should make it possible to provide a positional argument with a dash as first character
        // sadly doesn't fix the issue for the first argument so it is commented out
        // thereby one could say argtic does not support positionals starting with a dash
        // if (self.positional_index != 0) return null;

        // to reduce complexity we will assume two different algorithms, based on the existence of an equal sign
        // since in 'posix-style' we use --flag value and in gnu-style --flag=value
        // this decision was made by favoring reduced complexity over reduced code duplication and reduced code nesting
        if (std.mem.count(u8, self.argument_vector[self.argument_index], "=") == 0) {
            var flag_type: enum { default, short, long } = .default;
            var buffer = ArrayList(u8).init(self.allocator);
            defer buffer.deinit();

            for (self.argument_vector[self.argument_index], 0..) |char, index| {
                if (char == '-' and index < 2 and buffer.items.len == 0) {
                    switch (flag_type) {
                        .default => flag_type = .short,
                        .short => flag_type = .long,
                        .long => unreachable, // unreachable because of index < 2 check
                    }
                } else {
                    try buffer.append(char);
                }
            }

            const identifier = buffer.items; // using items instead of toOwnedSlice to prevent memory leak
            var flag: Flag = undefined;

            switch (flag_type) {
                .default => return null, // not a flag since '-' or '--' did not match
                .short => {
                    // originally an error, but this case is already captured by FlagNotFound in lexCompoundFlag
                    if (identifier.len != 1) @panic("deprecated error error.InvalidShortFlagLength");
                    flag = self.getFlagShort(identifier[0]) orelse return error.FlagNotFound;
                },
                .long => flag = self.getFlagLong(identifier) orelse return error.FlagNotFound,
            }

            if (flag.abort) self.abort_lexing = true;

            if (flag.value) {
                // skip an argument to access the following value
                self.argument_index += 1;
                if (self.argument_index >= self.argument_vector.len) return error.NoValueProvided;

                return Token{ .flag = .{
                    .name = flag.name,
                    .value = self.argument_vector[self.argument_index],
                } };
            } else {
                return Token{ .flag = .{
                    .name = flag.name,
                } };
            }
        } else {
            const argument = self.argument_vector[self.argument_index];

            if (argument.len <= 2) return null;
            if (!std.mem.eql(u8, argument[0..2], "--")) return null;
            if (std.mem.count(u8, argument, "=") != 1) return error.TooManyEqualSigns;

            var split = std.mem.splitScalar(u8, argument[2..], '=');

            const flag_name = split.next() orelse return error.SplitFlagValue;
            const flag_value = split.next() orelse return error.SplitFlagValue;

            if (self.getFlagLong(flag_name)) |flag| {
                if (!flag.value) return error.ValueNotExpected;
                if (flag.abort) self.abort_lexing = true;
            } else {
                return error.FlagNotFound;
            }

            return Token{ .flag = .{
                .name = flag_name,
                .value = flag_value,
            } };
        }
    }

    /// Lex for compound flags, grouped together by combining the shorts of flags
    fn lexCompoundFlag(self: *ArgumentTokenizer) ArgumentTokenizerError!?Token {
        const argument = self.argument_vector[self.argument_index];

        if (argument.len < 3) return null; // must be 1+2 char long, because otherwise it might just be a short flag
        if (argument[0] != '-') return null;
        if (argument[1] == '-') return null;

        var flags = ArrayList([]const u8).init(self.allocator);
        errdefer flags.deinit();

        for (argument[1..argument.len]) |char| {
            if (self.getFlagShort(char)) |flag| {
                if (flag.abort) self.abort_lexing = true;
                try flags.append(flag.name);
            } else {
                return error.FlagNotFound;
            }
        }

        return Token{ .compound_flag = .{
            .allocator = self.allocator,
            .flags = try flags.toOwnedSlice(),
        } };
    }

    /// Lex for subcommands, changing ArgumentTokenizer.specification to the specification of a matched subcommand in ArgumentSpecification.subcommands
    fn lexSubcommand(self: *ArgumentTokenizer) ArgumentTokenizerError!?Token {
        if (self.positional_index != 0) return null; // do not parse subcommands when positionals were already passed

        for (self.specification.subcommands) |specification| {
            if (std.mem.eql(u8, specification.name, self.argument_vector[self.argument_index])) {
                self.specification = specification;

                return Token{ .subcommand = .{
                    .name = specification.name,
                    .specification = specification,
                } };
            }
        }

        return null;
    }

    /// Lex for positional arguments, as specified in ArgumentSpecification.positionals
    fn lexPositional(self: *ArgumentTokenizer) ArgumentTokenizerError!?Token {
        if (self.positional_index >= self.specification.positionals.len) return null;

        const token = Token{ .positional = .{
            .name = self.specification.positionals[self.positional_index].name,
            .value = self.argument_vector[self.argument_index],
        } };

        self.positional_index += 1;

        return token;
    }

    /// Lex for additional positionals not captured by ArgumentSpecification.positionals
    fn lexExtraPositionals(self: *ArgumentTokenizer) ArgumentTokenizerError!?Token {
        if (self.specification.extra_positionals == null) return null;

        return Token{ .extra_positional = .{
            .name = self.specification.extra_positionals.?.name,
            .value = self.argument_vector[self.argument_index],
        } };
    }

    /// Forward one step in the tokenization process, return the produced Token
    pub fn nextToken(self: *ArgumentTokenizer) ArgumentTokenizerError!?Token {
        if (self.abort_lexing) return null;
        if (self.argument_index >= self.argument_vector.len) {
            // no more tokens left to parse
            try self.finalChecks();
            return null;
        }

        for (lexing_functions) |lexing_function| {
            if (try lexing_function(self)) |token| {
                self.argument_index += 1;
                return token;
            }
        }

        // handling exceptions, such as passing too many arguments that are not captured by any lexical function
        if (self.positional_index == self.specification.positionals.len) return error.AssumptionTooManyPositionals;

        // not using unreachable, since there might be a very small chance for failure
        @panic("unexpected error: the argument could not be tokenized");
    }

    /// A convenience method for collecting all tokens into a slice
    pub fn collectTokens(self: *ArgumentTokenizer, allocator: Allocator) ArgumentTokenizerError![]const Token {
        var tokens = ArrayList(Token).init(allocator);
        errdefer tokens.deinit();
        errdefer for (tokens.items) |token| if (token == .compound_flag) token.compound_flag.deinit();

        while (try self.nextToken()) |token| try tokens.append(token);

        return try tokens.toOwnedSlice();
    }
};

/// A struct for working with command-line arguments that have passed tokenization
pub const ArgumentProcessor = struct {
    /// The assumption is made that this struct will not be initialized manually,
    /// thus an allocator is stored for the initialization through the function parse,
    /// so that the method deinit can free the tokens returned by struct ArgumentTokenizer
    allocator: Allocator,
    /// Tokens, as returned by ArgumentTokenizer for further processing through this struct's methods
    tokens: []const ArgumentTokenizer.Token,
    /// The tokenizer is additionally provided as an attribute, although not used by this module
    tokenizer: ArgumentTokenizer,

    /// Initialize this struct by parsing an argument_vector using an ArgumentSpecification
    pub fn parse(allocator: Allocator, specification: ArgumentSpecification, argument_vector: []const []const u8) ArgumentTokenizerError!ArgumentProcessor {
        var tokenizer = ArgumentTokenizer{
            .allocator = allocator,
            .specification = specification,
            .argument_vector = argument_vector,
        };

        return ArgumentProcessor{
            .allocator = allocator,
            .tokens = try tokenizer.collectTokens(allocator),
            .tokenizer = tokenizer,
        };
    }

    /// Free the memory of the tokens stored
    pub fn deinit(self: ArgumentProcessor) void {
        for (self.tokens) |token| {
            // @hasDecl magic or similar does not work, thus we use simple union type checks
            if (token == .compound_flag) token.compound_flag.deinit();
        }
        self.allocator.free(self.tokens);
    }

    /// Return whether an optional or subcommand exists
    pub fn isArgument(self: ArgumentProcessor, searched_argument_name: []const u8) bool {
        for (self.tokens) |token| switch (token) {
            .flag => |flag| {
                if (std.mem.eql(u8, flag.name, searched_argument_name)) return true;
            },
            .compound_flag => |compound_flag| {
                for (compound_flag.flags) |flag_name| {
                    if (std.mem.eql(u8, flag_name, searched_argument_name)) return true;
                }
            },
            .positional => |positional| {
                if (std.mem.eql(u8, positional.name, searched_argument_name)) return true;
            },
            .subcommand => |subcommand| {
                if (std.mem.eql(u8, subcommand.name, searched_argument_name)) return true;
            },
            .extra_positional => |extra_positional| {
                if (std.mem.eql(u8, extra_positional.name, searched_argument_name)) return true;
            },
        };

        return false;
    }

    /// Return the first value of an argument
    pub fn getArgument(self: ArgumentProcessor, searched_key_name: []const u8) ?[]const u8 {
        for (self.tokens) |token| switch (token) {
            .flag => |flag| {
                if (std.mem.eql(u8, flag.name, searched_key_name)) return flag.value;
            },
            .positional => |positional| {
                if (std.mem.eql(u8, positional.name, searched_key_name)) return positional.value;
            },
            else => {},
        };

        return null;
    }

    /// Return the values of all optional arguments with the specified name
    pub fn getArguments(self: ArgumentProcessor, allocator: Allocator, searched_flag_name: []const u8) !?[]const []const u8 {
        var values = ArrayList([]const u8).init(allocator);

        for (self.tokens) |token| switch (token) {
            .flag => |flag| {
                if (std.mem.eql(u8, flag.name, searched_flag_name)) try values.append(flag.value.?);
            },
            else => {},
        };

        if (values.items.len == 0) return null;

        return try values.toOwnedSlice();
    }

    /// Return a slice of all additional positionals that were not captured by ArgumentSpecification.positionals
    pub fn getExtraPositionals(self: ArgumentProcessor, allocator: Allocator) Allocator.Error![]const []const u8 {
        var extra_positionals = ArrayList([]const u8).init(allocator);
        errdefer extra_positionals.deinit();

        for (self.tokens) |token| switch (token) {
            .extra_positional => |extra_positional| {
                try extra_positionals.append(extra_positional.value);
            },
            else => {},
        };

        return try extra_positionals.toOwnedSlice();
    }
};

/// Crappy and untested convenience function to build and write a short usage message to stdout at runtime
pub fn generateUsageMessage(specification: ArgumentSpecification) anyerror!void {
    const stdout = std.io.getStdOut().writer();
    const default_padding = " " ** 4;

    if (specification.short_description) |short_description| try stdout.print("{s}\n\n", .{short_description});

    try stdout.writeAll("Usage:\n");
    try stdout.print("{s}{s} ", .{ default_padding, specification.name });
    if (specification.flags.len != 0) try stdout.writeAll("[options] ");
    if (specification.subcommands.len != 0) try stdout.writeAll("[sub-commands] ");
    for (specification.positionals) |positional| try stdout.print("<{s}> ", .{positional.name});
    if (specification.extra_positionals) |extra_positionals| try stdout.print("[{s}...]", .{extra_positionals.name});
    try stdout.writeAll("\n\n");
}

/// Crappy and untested convenience function to build and write a default and quite detailed help message to stdout at runtime
pub fn generateHelpMessage(specification: ArgumentSpecification) anyerror!void {
    // This code is an absolute abomination, but I start getting annoyed by this project and this function is not a core component ¯\_(ツ)_/¯
    // Thus, I will throw in some useless comments to segment the code and make future code reading slightly less painful
    // I think better methods would be to utilize comptime or try to template more using Writer.print
    const stdout = std.io.getStdOut().writer();
    const default_padding = " " ** 4;

    try generateUsageMessage(specification);

    // search for the longest names to be able to calculate a new padding later, so that all help messages will be vertically aligned
    var longest_flag_name: usize = 0;
    for (specification.flags) |flag| if (flag.name.len > longest_flag_name) {
        longest_flag_name = flag.name.len;
    };

    var longest_subcommand_name: usize = 0;
    for (specification.subcommands) |subcommand| if (subcommand.name.len > longest_subcommand_name) {
        longest_subcommand_name = subcommand.name.len;
    };

    var longest_positional_name: usize = 0;
    for (specification.positionals) |positional| if (positional.name.len > longest_positional_name) {
        longest_positional_name = positional.name.len;
    };
    if (specification.extra_positionals) |extra_positionals| if (extra_positionals.name.len > longest_positional_name) {
        longest_positional_name = extra_positionals.name.len;
    };

    if (specification.long_description) |long_description| {
        var lines = std.mem.splitScalar(u8, long_description, '\n');
        try stdout.writeAll("Description:\n");
        while (lines.next()) |line| try stdout.print("{s}{s}\n", .{ default_padding, line });
        try stdout.writeAll("\n");
    }

    if (specification.positionals.len != 0) {
        try stdout.writeAll("Required:\n");
        for (specification.positionals) |positional| {
            try stdout.writeAll(default_padding);
            try stdout.writeAll(positional.name);

            // add padding to vertically align the option descriptions
            var index: usize = 0;
            while (index <= (longest_positional_name - positional.name.len + 2)) : (index += 1) {
                try stdout.writeAll(" ");
            }

            try stdout.writeAll(positional.help orelse " /");
            try stdout.writeAll("\n");
        }

        if (specification.extra_positionals) |extra_positionals| {
            try stdout.writeAll(default_padding);
            try stdout.writeAll(extra_positionals.name);

            // add padding to vertically align the option descriptions
            var index: usize = 0;
            while (index <= (longest_positional_name - extra_positionals.name.len + 2)) : (index += 1) {
                try stdout.writeAll(" ");
            }

            try stdout.writeAll(extra_positionals.help orelse " /");
            try stdout.writeAll("\n");
        }

        try stdout.writeAll("\n");
    }

    if (specification.flags.len != 0) {
        try stdout.writeAll("Options:\n");
        for (specification.flags) |flag| {
            // add short name
            try stdout.writeAll(default_padding);
            if (flag.short) |short| {
                try stdout.print("-{c}, ", .{short});
            } else {
                try stdout.writeAll("    ");
            }

            // add flag name
            try stdout.print("--{s}", .{flag.name});

            // add padding to vertically align the option descriptions
            var index: usize = 0;
            while (index <= (longest_flag_name - flag.name.len + 2)) : (index += 1) {
                try stdout.writeAll(" ");
            }

            // option description
            try stdout.writeAll(flag.help orelse " /");
            try stdout.writeAll("\n");
        }
        try stdout.writeAll("\n");
    }

    if (specification.subcommands.len != 0) {
        try stdout.writeAll("Sub-commands:\n");
        for (specification.subcommands) |subcommand| {
            try stdout.writeAll(default_padding);
            try stdout.writeAll(subcommand.name);

            // add padding to vertically align the option descriptions
            var index: usize = 0;
            while (index <= (longest_subcommand_name - subcommand.name.len + 2)) : (index += 1) {
                try stdout.writeAll(" ");
            }

            try stdout.writeAll(subcommand.short_description orelse " /");
            try stdout.writeAll("\n");
        }
        try stdout.writeAll("\n");
    }
}

/// A convenience function for writing a information about an ArgumentTokenizerError to stdout
pub fn defaultErrorHandler(tokenization_error: ArgumentTokenizerError) anyerror!void {
    const stdout = std.io.getStdErr().writer();

    switch (tokenization_error) {
        error.MissingPositionals => try stdout.writeAll("fatal: not all required arguments were provided\n"),
        error.FlagNotFound => try stdout.writeAll("fatal: a provided option does not exists or might be misspelled\n"),
        error.SplitFlagValue => try stdout.writeAll("fatal: a provided option could not be parsed for its assigned value\n"),
        error.AssumptionTooManyPositionals => try stdout.writeAll("fatal: too many arguments were presumably provided\n"),
        error.TooManyEqualSigns => try stdout.writeAll("fatal: options may only allow for one equal sign as part of the gnu-style syntax\n"),
        error.ValueNotExpected => try stdout.writeAll("fatal: a value was provided for an option that did not require one\n"),
        error.OutOfMemory => try stdout.writeAll("fatal: there is not enough free memory to parse the provided arguments\n"),
        error.NoValueProvided => try stdout.writeAll("fatal: a flag requires a value\n"),
    }
}

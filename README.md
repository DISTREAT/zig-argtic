# zig-argtic

A library for parsing command-line options, arguments, and sub-commands.

_Build using zig version: `0.14.1`_

## How does it compare to the POSIX and GNU conventions?

- An option requires a long name (GNU compatible; eg. `--long-option`)
- An option may have a single char name and start with one hyphen (similar to POSIX)
- An option may have a value (GNU compliant)
  - ...directly following as the next index inside the argument vector (eg. `-o file.txt`)
  - but may not follow directly after the option name (incompatible GNU/incompatible POSIX; eg. `-ofile.txt`)
- Options may be grouped in any order (POSIX compliant; eg. `-o -v` -> `-ov`)
- Options may appear multiple times (POSIX)
- Options precede required arguments (POSIX)
- Options may be supplied in any order (GNU)
- Options may be separated into option name and value through the use of an equal sign (GNU complicant; eg. `--name=value`)

[Source: POSIX Conventions](http://www.iitk.ac.in/esc101/05Aug/tutorial/essential/attributes/_posix.html)

[Source: GNU Conventions/Additions](https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html)

## Example

```zig
// simple example - reduced to a minimum
const specification = argtic.ArgumentSpecification{
    .name = "exe",
    .positionals = &[_]argtic.Positional{
        .{ .name = "value" },
    },
};

const argument_vector = try std.process.argsAlloc(allocator);
defer std.process.argsFree(allocator, argument_vector);

const arguments = try argtic.ArgumentProcessor.parse(allocator, specification, argument_vector[1..]);
defer arguments.deinit();

std.log.info("{s}", .{arguments.getArgument("value").?});
```

For more thorough examples, visit `examples/` and `src/tests.zig`.

[Required Arguments](https://github.com/DISTREAT/zig-argtic/blob/master/examples/positionals.zig)

[Optional Arguments](https://github.com/DISTREAT/zig-argtic/blob/master/examples/optionals.zig)

[Optional Positionals](https://github.com/DISTREAT/zig-argtic/blob/master/examples/extra_positionals.zig)

[Subcommands](https://github.com/DISTREAT/zig-argtic/blob/master/examples/subcommands.zig)

## Documentation

The documentation is created in the directory `docs/` when running `zig build`.

[Documentation](https://distreat.github.io/zig-argtic/)

## Appendix

This project was likely one of the most challenging projects I have written, especially because I struggle with parsers in general. Nonetheless, I did realize this project in the end and am more or less content, although not happy.

There is a lot of missing work, but I assume it's usable to the point where I could use it in future projects. To put it in perspective, this is probably already the 10th iteration I have written, and I finally got a decent structure down that I assume to be scalable and maintainable.

Anyway, don't underestimate the project of writing a CLI argument parser that supports subcommands, flags (with multiple value syntax), compound flags, and positional arguments. This project tested my limits again and agian and even made me consider using a PEG or regular expression parser - also - it's not like I started programming yesterday. Notably, the API took me some time to figure out, which is funny considering it's simplicity.

Every single stage of this project tested me and my idealistic bed-of-rose-loving ass. Considering all I've just said, I'd recommend writing an argument parser once in your life - it just makes you feel cured of all previous projects (or sad about your life choices) - because I hated it, especially in the final half-assed stages.

Now that I succeeded (more or less), you may consider this my magnum opus of yak shaving.

const std = @import("std");
const console_mod = @import("console.zig");
const Console = console_mod.Console;
const Text = @import("text.zig").Text;
const Style = @import("style.zig").Style;
const Segment = @import("segment.zig").Segment;
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const ColorSystem = color_mod.ColorSystem;

pub const PromptError = error{
    OutOfMemory,
    EndOfStream,
    InvalidInput,
    Cancelled,
};

pub const ValidationResult = union(enum) {
    valid,
    invalid: []const u8,
};

pub const ValidatorFn = *const fn ([]const u8) ValidationResult;

// Generic prompt for text input with rich features
pub const Prompt = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?[]const u8 = null,
    choices: ?[]const []const u8 = null,
    case_sensitive: bool = true,
    show_default: bool = true,
    show_choices: bool = true,
    password: bool = false,
    validator: ?ValidatorFn = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) Self {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: Self, c: *Console) Self {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: Self, default: []const u8) Self {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn withChoices(self: Self, choices: []const []const u8) Self {
        var p = self;
        p.choices = choices;
        return p;
    }

    pub fn caseSensitive(self: Self, sensitive: bool) Self {
        var p = self;
        p.case_sensitive = sensitive;
        return p;
    }

    pub fn showDefault(self: Self, show: bool) Self {
        var p = self;
        p.show_default = show;
        return p;
    }

    pub fn showChoices(self: Self, show: bool) Self {
        var p = self;
        p.show_choices = show;
        return p;
    }

    pub fn asPassword(self: Self, pwd: bool) Self {
        var p = self;
        p.password = pwd;
        return p;
    }

    pub fn withValidator(self: Self, v: ValidatorFn) Self {
        var p = self;
        p.validator = v;
        return p;
    }

    pub fn ask(self: Self) PromptError![]u8 {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn();

        while (true) {
            // Write prompt with markup support
            writeStyledPrompt(stdout, self.allocator, self.prompt_text) catch return PromptError.OutOfMemory;

            // Show choices
            if (self.show_choices) {
                if (self.choices) |choices| {
                    stdout.writeAll(" [") catch return PromptError.OutOfMemory;
                    for (choices, 0..) |choice, i| {
                        if (i > 0) stdout.writeAll("/") catch return PromptError.OutOfMemory;
                        stdout.writeAll(choice) catch return PromptError.OutOfMemory;
                    }
                    stdout.writeAll("]") catch return PromptError.OutOfMemory;
                }
            }

            // Show default
            if (self.show_default) {
                if (self.default) |def| {
                    stdout.print(" ({s})", .{def}) catch return PromptError.OutOfMemory;
                }
            }

            stdout.writeAll(": ") catch return PromptError.OutOfMemory;

            // Read input
            var input_buf: [4096]u8 = undefined;
            const line: ?[]u8 = if (self.password)
                readPassword(&input_buf, stdin) catch return PromptError.OutOfMemory
            else
                stdin.reader().readUntilDelimiterOrEof(&input_buf, '\n') catch return PromptError.OutOfMemory;

            if (line == null) {
                return PromptError.EndOfStream;
            }

            var trimmed = line.?;
            // Strip carriage return (Windows)
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
                trimmed = trimmed[0 .. trimmed.len - 1];
            }

            // Handle empty input with default
            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return self.allocator.dupe(u8, def) catch return PromptError.OutOfMemory;
                }
                // No default, reprompt
                continue;
            }

            // Validate against choices
            if (self.choices) |choices| {
                var valid = false;
                for (choices) |choice| {
                    if (self.case_sensitive) {
                        if (std.mem.eql(u8, trimmed, choice)) {
                            valid = true;
                            break;
                        }
                    } else {
                        if (std.ascii.eqlIgnoreCase(trimmed, choice)) {
                            valid = true;
                            // Use the canonical choice value
                            trimmed = @constCast(choice);
                            break;
                        }
                    }
                }
                if (!valid) {
                    printChoiceError(stdout, choices) catch {};
                    continue;
                }
            }

            // Run custom validator
            if (self.validator) |validate| {
                const result = validate(trimmed);
                switch (result) {
                    .valid => {},
                    .invalid => |msg| {
                        printValidationError(stdout, msg) catch {};
                        continue;
                    },
                }
            }

            return self.allocator.dupe(u8, trimmed) catch return PromptError.OutOfMemory;
        }
    }
};

// Integer prompt with bounds validation
pub const IntPrompt = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?i64 = null,
    min: ?i64 = null,
    max: ?i64 = null,
    show_default: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) Self {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: Self, c: *Console) Self {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: Self, default: i64) Self {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn withMin(self: Self, m: i64) Self {
        var p = self;
        p.min = m;
        return p;
    }

    pub fn withMax(self: Self, m: i64) Self {
        var p = self;
        p.max = m;
        return p;
    }

    pub fn showDefault(self: Self, show: bool) Self {
        var p = self;
        p.show_default = show;
        return p;
    }

    pub fn ask(self: Self) PromptError!i64 {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn();

        while (true) {
            // Write prompt with markup support
            writeStyledPrompt(stdout, self.allocator, self.prompt_text) catch return PromptError.OutOfMemory;

            // Show bounds hint
            if (self.min != null or self.max != null) {
                stdout.writeAll(" [") catch return PromptError.OutOfMemory;
                if (self.min) |m| {
                    stdout.print("{d}", .{m}) catch return PromptError.OutOfMemory;
                }
                stdout.writeAll("-") catch return PromptError.OutOfMemory;
                if (self.max) |m| {
                    stdout.print("{d}", .{m}) catch return PromptError.OutOfMemory;
                }
                stdout.writeAll("]") catch return PromptError.OutOfMemory;
            }

            // Show default
            if (self.show_default) {
                if (self.default) |def| {
                    stdout.print(" ({d})", .{def}) catch return PromptError.OutOfMemory;
                }
            }

            stdout.writeAll(": ") catch return PromptError.OutOfMemory;

            // Read input
            var input_buf: [256]u8 = undefined;
            const line = stdin.reader().readUntilDelimiterOrEof(&input_buf, '\n') catch return PromptError.OutOfMemory;

            if (line == null) {
                return PromptError.EndOfStream;
            }

            var trimmed = line.?;
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
                trimmed = trimmed[0 .. trimmed.len - 1];
            }

            // Handle empty with default
            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return def;
                }
                continue;
            }

            // Parse integer
            const value = std.fmt.parseInt(i64, trimmed, 10) catch {
                printValidationError(stdout, "Please enter a valid integer") catch {};
                continue;
            };

            // Validate bounds
            if (self.min) |m| {
                if (value < m) {
                    var buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Value must be at least {d}", .{m}) catch "Value too small";
                    printValidationError(stdout, msg) catch {};
                    continue;
                }
            }

            if (self.max) |m| {
                if (value > m) {
                    var buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Value must be at most {d}", .{m}) catch "Value too large";
                    printValidationError(stdout, msg) catch {};
                    continue;
                }
            }

            return value;
        }
    }
};

// Float prompt with bounds validation
pub const FloatPrompt = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?f64 = null,
    min: ?f64 = null,
    max: ?f64 = null,
    show_default: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) Self {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: Self, c: *Console) Self {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: Self, default: f64) Self {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn withMin(self: Self, m: f64) Self {
        var p = self;
        p.min = m;
        return p;
    }

    pub fn withMax(self: Self, m: f64) Self {
        var p = self;
        p.max = m;
        return p;
    }

    pub fn showDefault(self: Self, show: bool) Self {
        var p = self;
        p.show_default = show;
        return p;
    }

    pub fn ask(self: Self) PromptError!f64 {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn();

        while (true) {
            // Write prompt with markup support
            writeStyledPrompt(stdout, self.allocator, self.prompt_text) catch return PromptError.OutOfMemory;

            // Show bounds hint
            if (self.min != null or self.max != null) {
                stdout.writeAll(" [") catch return PromptError.OutOfMemory;
                if (self.min) |m| {
                    stdout.print("{d:.2}", .{m}) catch return PromptError.OutOfMemory;
                }
                stdout.writeAll("-") catch return PromptError.OutOfMemory;
                if (self.max) |m| {
                    stdout.print("{d:.2}", .{m}) catch return PromptError.OutOfMemory;
                }
                stdout.writeAll("]") catch return PromptError.OutOfMemory;
            }

            // Show default
            if (self.show_default) {
                if (self.default) |def| {
                    stdout.print(" ({d:.2})", .{def}) catch return PromptError.OutOfMemory;
                }
            }

            stdout.writeAll(": ") catch return PromptError.OutOfMemory;

            // Read input
            var input_buf: [256]u8 = undefined;
            const line = stdin.reader().readUntilDelimiterOrEof(&input_buf, '\n') catch return PromptError.OutOfMemory;

            if (line == null) {
                return PromptError.EndOfStream;
            }

            var trimmed = line.?;
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
                trimmed = trimmed[0 .. trimmed.len - 1];
            }

            // Handle empty with default
            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return def;
                }
                continue;
            }

            // Parse float
            const value = std.fmt.parseFloat(f64, trimmed) catch {
                printValidationError(stdout, "Please enter a valid number") catch {};
                continue;
            };

            // Validate bounds
            if (self.min) |m| {
                if (value < m) {
                    var buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Value must be at least {d:.2}", .{m}) catch "Value too small";
                    printValidationError(stdout, msg) catch {};
                    continue;
                }
            }

            if (self.max) |m| {
                if (value > m) {
                    var buf: [64]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Value must be at most {d:.2}", .{m}) catch "Value too large";
                    printValidationError(stdout, msg) catch {};
                    continue;
                }
            }

            return value;
        }
    }
};

// Confirm prompt for yes/no questions
pub const Confirm = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?bool = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) Self {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: Self, c: *Console) Self {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: Self, default: bool) Self {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn ask(self: Self) PromptError!bool {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn();

        while (true) {
            // Write prompt with markup support
            writeStyledPrompt(stdout, self.allocator, self.prompt_text) catch return PromptError.OutOfMemory;

            // Show choices with default highlighted
            stdout.writeAll(" [") catch return PromptError.OutOfMemory;
            if (self.default) |def| {
                if (def) {
                    stdout.writeAll("Y/n") catch return PromptError.OutOfMemory;
                } else {
                    stdout.writeAll("y/N") catch return PromptError.OutOfMemory;
                }
            } else {
                stdout.writeAll("y/n") catch return PromptError.OutOfMemory;
            }
            stdout.writeAll("]: ") catch return PromptError.OutOfMemory;

            // Read input
            var input_buf: [64]u8 = undefined;
            const line = stdin.reader().readUntilDelimiterOrEof(&input_buf, '\n') catch return PromptError.OutOfMemory;

            if (line == null) {
                return PromptError.EndOfStream;
            }

            var trimmed = line.?;
            if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '\r') {
                trimmed = trimmed[0 .. trimmed.len - 1];
            }

            // Handle empty with default
            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return def;
                }
                continue;
            }

            // Check for yes/no variants
            var lower_buf: [64]u8 = undefined;
            const lower = std.ascii.lowerString(lower_buf[0..trimmed.len], trimmed);
            if (std.mem.eql(u8, lower, "y") or
                std.mem.eql(u8, lower, "yes") or
                std.mem.eql(u8, lower, "true") or
                std.mem.eql(u8, lower, "1"))
            {
                return true;
            }

            if (std.mem.eql(u8, lower, "n") or
                std.mem.eql(u8, lower, "no") or
                std.mem.eql(u8, lower, "false") or
                std.mem.eql(u8, lower, "0"))
            {
                return false;
            }

            printValidationError(stdout, "Please enter y or n") catch {};
        }
    }
};

// Helper to write a styled prompt (supports markup)
fn writeStyledPrompt(writer: anytype, allocator: std.mem.Allocator, prompt_text: []const u8) !void {
    var txt = Text.fromMarkup(allocator, prompt_text) catch {
        // Fall back to plain text if markup parsing fails
        try writer.writeAll(prompt_text);
        return;
    };
    defer txt.deinit();

    const segments = txt.render(allocator) catch {
        try writer.writeAll(prompt_text);
        return;
    };
    defer allocator.free(segments);

    for (segments) |seg| {
        if (seg.style) |style| {
            if (!style.isEmpty()) {
                try style.renderAnsi(.truecolor, writer);
            }
        }
        try writer.writeAll(seg.text);
        if (seg.style) |style| {
            if (!style.isEmpty()) {
                try Style.renderReset(writer);
            }
        }
    }
}

fn printValidationError(writer: anytype, msg: []const u8) !void {
    try writer.writeAll("\x1b[31mError: ");
    try writer.writeAll(msg);
    try writer.writeAll("\x1b[0m\n");
}

fn printChoiceError(writer: anytype, choices: []const []const u8) !void {
    try writer.writeAll("\x1b[31mPlease select from: ");
    for (choices, 0..) |choice, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll(choice);
    }
    try writer.writeAll("\x1b[0m\n");
}

fn readPassword(buf: []u8, stdin: std.fs.File) !?[]u8 {
    const builtin = @import("builtin");
    const stdout = std.io.getStdOut().writer();

    if (builtin.os.tag == .windows) {
        return readPasswordWindows(buf, stdin, stdout);
    } else if (builtin.os.tag == .wasi or builtin.cpu.arch == .wasm32) {
        // No raw mode on WASM, fall back to regular read
        return stdin.reader().readUntilDelimiterOrEof(buf, '\n');
    } else {
        return readPasswordPosix(buf, stdin, stdout);
    }
}

fn readPasswordPosix(buf: []u8, stdin: std.fs.File, stdout: anytype) !?[]u8 {
    const posix = std.posix;
    const fd = stdin.handle;

    // Save current terminal settings
    var orig_termios: posix.termios = undefined;
    const tcgetattr_result = posix.system.tcgetattr(fd, &orig_termios);
    if (tcgetattr_result != 0) {
        // Fall back to regular read if tcgetattr fails
        return stdin.reader().readUntilDelimiterOrEof(buf, '\n');
    }

    // Disable echo
    var new_termios = orig_termios;
    new_termios.lflag.ECHO = false;

    const tcsetattr_result = posix.system.tcsetattr(fd, .FLUSH, &new_termios);
    if (tcsetattr_result != 0) {
        return stdin.reader().readUntilDelimiterOrEof(buf, '\n');
    }

    // Ensure we restore terminal settings
    defer {
        _ = posix.system.tcsetattr(fd, .FLUSH, &orig_termios);
        stdout.writeAll("\n") catch {};
    }

    // Read character by character, showing asterisks
    var len: usize = 0;
    while (len < buf.len - 1) {
        const byte_read = stdin.reader().readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        if (byte_read == '\n' or byte_read == '\r') {
            break;
        }

        if (byte_read == 127 or byte_read == 8) {
            // Backspace
            if (len > 0) {
                len -= 1;
                stdout.writeAll("\x08 \x08") catch {};
            }
        } else if (byte_read >= 32) {
            buf[len] = byte_read;
            len += 1;
            stdout.writeAll("*") catch {};
        }
    }

    if (len == 0) {
        return null;
    }

    return buf[0..len];
}

fn readPasswordWindows(buf: []u8, stdin: std.fs.File, stdout: anytype) !?[]u8 {
    _ = stdin;
    const windows = std.os.windows;

    const handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch {
        return null;
    };

    // Get current mode
    var orig_mode: windows.DWORD = 0;
    if (windows.kernel32.GetConsoleMode(handle, &orig_mode) == 0) {
        return null;
    }

    // Disable echo and line input for character-by-character reading
    const ENABLE_ECHO_INPUT: windows.DWORD = 0x0004;
    const ENABLE_LINE_INPUT: windows.DWORD = 0x0002;
    const new_mode = orig_mode & ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT);

    if (windows.kernel32.SetConsoleMode(handle, new_mode) == 0) {
        return null;
    }

    defer {
        _ = windows.kernel32.SetConsoleMode(handle, orig_mode);
        stdout.writeAll("\n") catch {};
    }

    var len: usize = 0;
    while (len < buf.len - 1) {
        var chars_read: windows.DWORD = 0;
        var char_buf: [1]u8 = undefined;

        const read_result = windows.kernel32.ReadConsoleA(
            handle,
            &char_buf,
            1,
            &chars_read,
            null,
        );

        if (read_result == 0 or chars_read == 0) {
            break;
        }

        const byte = char_buf[0];

        if (byte == '\n' or byte == '\r') {
            break;
        }

        if (byte == 8) {
            // Backspace
            if (len > 0) {
                len -= 1;
                stdout.writeAll("\x08 \x08") catch {};
            }
        } else if (byte >= 32) {
            buf[len] = byte;
            len += 1;
            stdout.writeAll("*") catch {};
        }
    }

    if (len == 0) {
        return null;
    }

    return buf[0..len];
}

// Tests
test "Prompt builder" {
    const allocator = std.testing.allocator;
    const p = Prompt.init(allocator, "Name")
        .withDefault("John")
        .withChoices(&[_][]const u8{ "John", "Jane", "Bob" })
        .caseSensitive(false)
        .showDefault(true)
        .showChoices(true);

    try std.testing.expectEqualStrings("Name", p.prompt_text);
    try std.testing.expectEqualStrings("John", p.default.?);
    try std.testing.expect(!p.case_sensitive);
    try std.testing.expect(p.choices != null);
}

test "IntPrompt builder" {
    const allocator = std.testing.allocator;
    const p = IntPrompt.init(allocator, "Age")
        .withDefault(25)
        .withMin(0)
        .withMax(150);

    try std.testing.expectEqualStrings("Age", p.prompt_text);
    try std.testing.expectEqual(@as(i64, 25), p.default.?);
    try std.testing.expectEqual(@as(i64, 0), p.min.?);
    try std.testing.expectEqual(@as(i64, 150), p.max.?);
}

test "FloatPrompt builder" {
    const allocator = std.testing.allocator;
    const p = FloatPrompt.init(allocator, "Price")
        .withDefault(9.99)
        .withMin(0.0)
        .withMax(1000.0);

    try std.testing.expectEqualStrings("Price", p.prompt_text);
    try std.testing.expectEqual(@as(f64, 9.99), p.default.?);
    try std.testing.expectEqual(@as(f64, 0.0), p.min.?);
    try std.testing.expectEqual(@as(f64, 1000.0), p.max.?);
}

test "Confirm builder" {
    const allocator = std.testing.allocator;
    const p = Confirm.init(allocator, "Continue?")
        .withDefault(true);

    try std.testing.expectEqualStrings("Continue?", p.prompt_text);
    try std.testing.expect(p.default.?);
}

test "Prompt with password" {
    const allocator = std.testing.allocator;
    const p = Prompt.init(allocator, "Password")
        .asPassword(true);

    try std.testing.expect(p.password);
}

test "Prompt with validator" {
    const allocator = std.testing.allocator;

    const validateNotEmpty = struct {
        fn validate(input: []const u8) ValidationResult {
            if (input.len == 0) {
                return .{ .invalid = "Input cannot be empty" };
            }
            return .valid;
        }
    }.validate;

    const p = Prompt.init(allocator, "Name")
        .withValidator(validateNotEmpty);

    try std.testing.expect(p.validator != null);
}

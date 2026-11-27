const std = @import("std");
const Console = @import("console.zig").Console;
const Text = @import("text.zig").Text;
const Style = @import("style.zig").Style;
const assert = @import("assert").assert;
const terminal = @import("terminal.zig");
const host_mod = @import("host.zig");
const Host = host_mod.Host;
const HostWriter = host_mod.HostWriter;

pub const PromptError = error{
    OutOfMemory,
    EndOfStream,
    InvalidInput,
    Cancelled,
    WriteFailed,
};

const Message = struct {
    bytes: [64]u8 = undefined,
    length: u8 = 0,

    fn format(comptime fmt: []const u8, args: anytype) Message {
        var message: Message = .{};
        const text = std.fmt.bufPrint(&message.bytes, fmt, args) catch return .{};
        message.length = @intCast(text.len);
        assert(message.length <= message.bytes.len);
        return message;
    }

    fn slice(self: *const Message) []const u8 {
        if (self.length == 0) return "Value out of range";
        return self.bytes[0..self.length];
    }
};

pub const ValidationResult = union(enum) {
    valid,
    invalid: []const u8,
};

pub const ValidatorFn = *const fn ([]const u8) ValidationResult;

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

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) Prompt {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: Prompt, c: *Console) Prompt {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: Prompt, default: []const u8) Prompt {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn withChoices(self: Prompt, choices: []const []const u8) Prompt {
        var p = self;
        p.choices = choices;
        return p;
    }

    pub fn caseSensitive(self: Prompt, sensitive: bool) Prompt {
        var p = self;
        p.case_sensitive = sensitive;
        return p;
    }

    pub fn showDefault(self: Prompt, show: bool) Prompt {
        var p = self;
        p.show_default = show;
        return p;
    }

    pub fn showChoices(self: Prompt, show: bool) Prompt {
        var p = self;
        p.show_choices = show;
        return p;
    }

    pub fn asPassword(self: Prompt, pwd: bool) Prompt {
        var p = self;
        p.password = pwd;
        return p;
    }

    pub fn withValidator(self: Prompt, v: ValidatorFn) Prompt {
        var p = self;
        p.validator = v;
        return p;
    }

    pub fn ask(self: Prompt, io: std.Io, environ: std.process.Environ) PromptError![]u8 {
        var source = host_mod.Source.from_io(io, environ);
        return self.ask_host(source.host());
    }

    pub fn ask_host(self: Prompt, host: Host) PromptError![]u8 {
        const colors = prompt_colors(self.console, terminal.detect_host(host));
        var output = HostWriter.init(host, .stdout, &.{});
        const stdout = &output.interface;
        assert(stdout.buffer.len == 0);

        while (true) {
            self.write_question(stdout, colors) catch return PromptError.WriteFailed;

            var input_buf: [4096]u8 = undefined;
            const line = (if (self.password)
                read_secret(host, &input_buf, stdout)
            else
                host.read_line(&input_buf)) catch |err| return read_failure(err);

            const raw = line orelse return PromptError.EndOfStream;
            var trimmed = stripCarriageReturn(raw);

            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return self.allocator.dupe(u8, def) catch return PromptError.OutOfMemory;
                }
                continue;
            }

            if (self.choices) |choices| {
                if (self.match_choice(choices, trimmed)) |choice| {
                    if (!self.case_sensitive) trimmed = @constCast(choice);
                } else {
                    printChoiceError(stdout, choices, colors) catch return PromptError.WriteFailed;
                    continue;
                }
            }

            if (self.validator) |validate| {
                switch (validate(trimmed)) {
                    .valid => {},
                    .invalid => |msg| {
                        printValidationError(stdout, msg, colors) catch return PromptError.WriteFailed;
                        continue;
                    },
                }
            }

            assert(trimmed.len > 0);
            return self.allocator.dupe(u8, trimmed) catch return PromptError.OutOfMemory;
        }
    }

    fn match_choice(self: Prompt, choices: []const []const u8, text: []const u8) ?[]const u8 {
        assert(text.len > 0);
        for (choices) |choice| {
            const matches = if (self.case_sensitive)
                std.mem.eql(u8, text, choice)
            else
                std.ascii.eqlIgnoreCase(text, choice);
            if (matches) return choice;
        }
        return null;
    }

    fn write_question(self: Prompt, stdout: *std.Io.Writer, colors: bool) !void {
        assert(stdout.buffer.len == 0);
        try writeStyledPrompt(stdout, self.allocator, self.prompt_text, colors);
        if (self.show_choices and self.choices != null) {
            try stdout.writeAll(" [");
            for (self.choices.?, 0..) |choice, i| {
                if (i > 0) try stdout.writeAll("/");
                try stdout.writeAll(choice);
            }
            try stdout.writeAll("]");
        }
        if (self.show_default and self.default != null) {
            try stdout.print(" ({s})", .{self.default.?});
        }
        try stdout.writeAll(": ");
        assert(stdout.end == 0);
    }
};

pub const IntPrompt = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?i64 = null,
    min: ?i64 = null,
    max: ?i64 = null,
    show_default: bool = true,

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) IntPrompt {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: IntPrompt, c: *Console) IntPrompt {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: IntPrompt, default: i64) IntPrompt {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn withMin(self: IntPrompt, m: i64) IntPrompt {
        var p = self;
        p.min = m;
        return p;
    }

    pub fn withMax(self: IntPrompt, m: i64) IntPrompt {
        var p = self;
        p.max = m;
        return p;
    }

    pub fn showDefault(self: IntPrompt, show: bool) IntPrompt {
        var p = self;
        p.show_default = show;
        return p;
    }

    pub fn ask(self: IntPrompt, io: std.Io, environ: std.process.Environ) PromptError!i64 {
        var source = host_mod.Source.from_io(io, environ);
        return self.ask_host(source.host());
    }

    pub fn ask_host(self: IntPrompt, host: Host) PromptError!i64 {
        const colors = prompt_colors(self.console, terminal.detect_host(host));
        var output = HostWriter.init(host, .stdout, &.{});
        const stdout = &output.interface;
        assert(stdout.buffer.len == 0);

        while (true) {
            self.write_question(stdout, colors) catch return PromptError.WriteFailed;

            var input_buf: [256]u8 = undefined;
            const line = host.read_line(&input_buf) catch |err| return read_failure(err);

            const raw = line orelse return PromptError.EndOfStream;
            const trimmed = stripCarriageReturn(raw);

            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return def;
                }
                continue;
            }

            const value = std.fmt.parseInt(i64, trimmed, 10) catch {
                printValidationError(stdout, "Please enter a valid integer", colors) catch {
                    return PromptError.WriteFailed;
                };
                continue;
            };

            if (self.range_message(value)) |message| {
                printValidationError(stdout, message.slice(), colors) catch {
                    return PromptError.WriteFailed;
                };
                continue;
            }

            assert((self.min orelse value) <= value and value <= (self.max orelse value));
            return value;
        }
    }

    fn range_message(self: IntPrompt, value: i64) ?Message {
        if (self.min) |m| {
            if (value < m) return Message.format("Value must be at least {d}", .{m});
        }
        if (self.max) |m| {
            if (value > m) return Message.format("Value must be at most {d}", .{m});
        }
        assert(self.min == null or value >= self.min.?);
        assert(self.max == null or value <= self.max.?);
        return null;
    }

    fn write_question(self: IntPrompt, stdout: *std.Io.Writer, colors: bool) !void {
        assert(stdout.buffer.len == 0);
        try writeStyledPrompt(stdout, self.allocator, self.prompt_text, colors);
        if (self.min != null or self.max != null) {
            try stdout.writeAll(" [");
            if (self.min) |m| try stdout.print("{d}", .{m});
            try stdout.writeAll("-");
            if (self.max) |m| try stdout.print("{d}", .{m});
            try stdout.writeAll("]");
        }
        if (self.show_default and self.default != null) {
            try stdout.print(" ({d})", .{self.default.?});
        }
        try stdout.writeAll(": ");
        assert(stdout.end == 0);
    }
};

pub const FloatPrompt = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?f64 = null,
    min: ?f64 = null,
    max: ?f64 = null,
    show_default: bool = true,

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) FloatPrompt {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: FloatPrompt, c: *Console) FloatPrompt {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: FloatPrompt, default: f64) FloatPrompt {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn withMin(self: FloatPrompt, m: f64) FloatPrompt {
        var p = self;
        p.min = m;
        return p;
    }

    pub fn withMax(self: FloatPrompt, m: f64) FloatPrompt {
        var p = self;
        p.max = m;
        return p;
    }

    pub fn showDefault(self: FloatPrompt, show: bool) FloatPrompt {
        var p = self;
        p.show_default = show;
        return p;
    }

    pub fn ask(self: FloatPrompt, io: std.Io, environ: std.process.Environ) PromptError!f64 {
        var source = host_mod.Source.from_io(io, environ);
        return self.ask_host(source.host());
    }

    pub fn ask_host(self: FloatPrompt, host: Host) PromptError!f64 {
        const colors = prompt_colors(self.console, terminal.detect_host(host));
        var output = HostWriter.init(host, .stdout, &.{});
        const stdout = &output.interface;
        assert(stdout.buffer.len == 0);

        while (true) {
            self.write_question(stdout, colors) catch return PromptError.WriteFailed;

            var input_buf: [256]u8 = undefined;
            const line = host.read_line(&input_buf) catch |err| return read_failure(err);

            const raw = line orelse return PromptError.EndOfStream;
            const trimmed = stripCarriageReturn(raw);

            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return def;
                }
                continue;
            }

            const value = std.fmt.parseFloat(f64, trimmed) catch {
                printValidationError(stdout, "Please enter a valid number", colors) catch {
                    return PromptError.WriteFailed;
                };
                continue;
            };

            if (self.range_message(value)) |message| {
                printValidationError(stdout, message.slice(), colors) catch {
                    return PromptError.WriteFailed;
                };
                continue;
            }

            return value;
        }
    }

    fn range_message(self: FloatPrompt, value: f64) ?Message {
        if (self.min) |m| {
            if (value < m) return Message.format("Value must be at least {d:.2}", .{m});
        }
        if (self.max) |m| {
            if (value > m) return Message.format("Value must be at most {d:.2}", .{m});
        }
        assert(self.min == null or !(value < self.min.?));
        assert(self.max == null or !(value > self.max.?));
        return null;
    }

    fn write_question(self: FloatPrompt, stdout: *std.Io.Writer, colors: bool) !void {
        assert(stdout.buffer.len == 0);
        try writeStyledPrompt(stdout, self.allocator, self.prompt_text, colors);
        if (self.min != null or self.max != null) {
            try stdout.writeAll(" [");
            if (self.min) |m| try stdout.print("{d:.2}", .{m});
            try stdout.writeAll("-");
            if (self.max) |m| try stdout.print("{d:.2}", .{m});
            try stdout.writeAll("]");
        }
        if (self.show_default and self.default != null) {
            try stdout.print(" ({d:.2})", .{self.default.?});
        }
        try stdout.writeAll(": ");
        assert(stdout.end == 0);
    }
};

pub const Confirm = struct {
    allocator: std.mem.Allocator,
    console: ?*Console = null,
    prompt_text: []const u8,
    default: ?bool = null,

    pub fn init(allocator: std.mem.Allocator, prompt_text: []const u8) Confirm {
        return .{
            .allocator = allocator,
            .prompt_text = prompt_text,
        };
    }

    pub fn withConsole(self: Confirm, c: *Console) Confirm {
        var p = self;
        p.console = c;
        return p;
    }

    pub fn withDefault(self: Confirm, default: bool) Confirm {
        var p = self;
        p.default = default;
        return p;
    }

    pub fn ask(self: Confirm, io: std.Io, environ: std.process.Environ) PromptError!bool {
        var source = host_mod.Source.from_io(io, environ);
        return self.ask_host(source.host());
    }

    pub fn ask_host(self: Confirm, host: Host) PromptError!bool {
        const colors = prompt_colors(self.console, terminal.detect_host(host));
        var output = HostWriter.init(host, .stdout, &.{});
        const stdout = &output.interface;
        assert(stdout.buffer.len == 0);

        while (true) {
            writeStyledPrompt(stdout, self.allocator, self.prompt_text, colors) catch {
                return PromptError.WriteFailed;
            };

            const hint = if (self.default) |def|
                if (def) "Y/n" else "y/N"
            else
                "y/n";
            stdout.print(" [{s}]: ", .{hint}) catch return PromptError.WriteFailed;

            var input_buf: [64]u8 = undefined;
            const line = host.read_line(&input_buf) catch |err| return read_failure(err);

            const raw = line orelse return PromptError.EndOfStream;
            const trimmed = stripCarriageReturn(raw);

            if (trimmed.len == 0) {
                if (self.default) |def| {
                    return def;
                }
                continue;
            }

            var lower_buf: [64]u8 = undefined;
            const lower = std.ascii.lowerString(lower_buf[0..trimmed.len], trimmed);

            assert(lower.len == trimmed.len);
            if (isAffirmative(lower)) return true;
            if (isNegative(lower)) return false;

            printValidationError(stdout, "Please enter y or n", colors) catch {
                return PromptError.WriteFailed;
            };
        }
    }
};

fn stripCarriageReturn(input: []u8) []u8 {
    if (input.len > 0 and input[input.len - 1] == '\r') {
        return input[0 .. input.len - 1];
    }
    return input;
}

fn isAffirmative(input: []const u8) bool {
    return std.mem.eql(u8, input, "y") or
        std.mem.eql(u8, input, "yes") or
        std.mem.eql(u8, input, "true") or
        std.mem.eql(u8, input, "1");
}

fn isNegative(input: []const u8) bool {
    return std.mem.eql(u8, input, "n") or
        std.mem.eql(u8, input, "no") or
        std.mem.eql(u8, input, "false") or
        std.mem.eql(u8, input, "0");
}

fn writeStyledPrompt(
    writer: anytype,
    allocator: std.mem.Allocator,
    prompt_text: []const u8,
    colors: bool,
) !void {
    var txt = Text.fromMarkup(allocator, prompt_text) catch {
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
        const has_style = if (seg.style) |s| !s.isEmpty() else false;
        if (has_style and colors) try seg.style.?.renderAnsi(.truecolor, writer);
        try writer.writeAll(seg.text);
        if (has_style and colors) try Style.renderReset(writer);
    }
}

fn printValidationError(writer: anytype, msg: []const u8, colors: bool) !void {
    if (colors) try writer.writeAll("\x1b[31m");
    try writer.writeAll("Error: ");
    try writer.writeAll(msg);
    if (colors) try Style.renderReset(writer);
    try writer.writeAll("\n");
}

fn printChoiceError(writer: anytype, choices: []const []const u8, colors: bool) !void {
    if (colors) try writer.writeAll("\x1b[31m");
    try writer.writeAll("Please select from: ");
    for (choices, 0..) |choice, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.writeAll(choice);
    }
    if (colors) try Style.renderReset(writer);
    try writer.writeAll("\n");
}

fn prompt_colors(console: ?*Console, info: terminal.TerminalInfo) bool {
    return if (console) |c|
        !c.options.no_color and (c.options.color_system != null or !c.terminal_info.no_color)
    else
        !info.no_color;
}

fn read_failure(err: host_mod.Error) PromptError {
    assert(err != error.FileUnavailable);
    return switch (err) {
        error.LineTooLong => PromptError.OutOfMemory,
        error.WriteFailed => PromptError.WriteFailed,
        else => PromptError.EndOfStream,
    };
}

fn read_secret(host: Host, buffer: []u8, stdout: *std.Io.Writer) host_mod.Error!?[]u8 {
    assert(buffer.len > 1);
    if (!host.set_mode(.password_input, true)) return host.read_line(buffer);
    const result = read_masked(host, buffer, stdout);
    _ = host.set_mode(.password_input, false);
    stdout.writeAll("\n") catch return error.WriteFailed;
    assert(stdout.end == 0);
    return result;
}

fn read_masked(host: Host, buffer: []u8, stdout: *std.Io.Writer) host_mod.Error!?[]u8 {
    assert(buffer.len > 1);
    var length: usize = 0;
    while (length < buffer.len - 1) {
        var key: [1]u8 = undefined;
        const count = try host.read(&key);
        if (count == 0) break;
        const byte = key[0];
        if (byte == '\n' or byte == '\r') break;
        if (byte == 127 or byte == 8) {
            if (length == 0) continue;
            length -= 1;
            stdout.writeAll("\x08 \x08") catch return error.WriteFailed;
        } else if (byte >= 32) {
            buffer[length] = byte;
            length += 1;
            stdout.writeAll("*") catch return error.WriteFailed;
        }
    }
    assert(length < buffer.len);
    if (length == 0) return null;
    return buffer[0..length];
}

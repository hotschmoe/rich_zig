const std = @import("std");
const Style = @import("style.zig").Style;
const Segment = @import("segment.zig").Segment;
const segment = @import("segment.zig");
const Text = @import("text.zig").Text;
const ColorSystem = @import("color.zig").ColorSystem;
const Color = @import("color.zig").Color;
const terminal = @import("terminal.zig");
const markup = @import("markup.zig");

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }

    pub fn style(self: LogLevel) Style {
        return switch (self) {
            .debug => Style.empty.dim(),
            .info => Style.empty,
            .warn => Style.empty.foreground(Color.yellow),
            .err => Style.empty.foreground(Color.red),
        };
    }
};

pub const ConsoleOptions = struct {
    width: ?u16 = null,
    height: ?u16 = null,
    color_system: ?ColorSystem = null,
    force_terminal: bool = false,
    no_color: bool = false,
    tab_size: u8 = 8,
    record: bool = false,
};

pub const Console = struct {
    allocator: std.mem.Allocator,
    options: ConsoleOptions,
    terminal_info: terminal.TerminalInfo,
    current_style: Style,
    capture_buffer: ?std.ArrayList(u8),
    write_buffer: []u8,
    write_buffer_owned: bool,

    const DEFAULT_BUFFER_SIZE = 4096;

    pub fn init(allocator: std.mem.Allocator) Console {
        return initWithOptions(allocator, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, options: ConsoleOptions) Console {
        const info = terminal.detect();
        _ = terminal.enableVirtualTerminal();

        const buffer = allocator.alloc(u8, DEFAULT_BUFFER_SIZE) catch unreachable;

        return .{
            .allocator = allocator,
            .options = options,
            .terminal_info = info,
            .current_style = Style.empty,
            .capture_buffer = if (options.record) std.ArrayList(u8).empty else null,
            .write_buffer = buffer,
            .write_buffer_owned = true,
        };
    }

    pub fn deinit(self: *Console) void {
        if (self.write_buffer_owned) {
            self.allocator.free(self.write_buffer);
        }
        if (self.capture_buffer) |*buf| {
            buf.deinit(self.allocator);
        }
    }

    pub fn width(self: Console) u16 {
        return self.options.width orelse self.terminal_info.width;
    }

    pub fn height(self: Console) u16 {
        return self.options.height orelse self.terminal_info.height;
    }

    pub fn colorSystem(self: Console) ColorSystem {
        if (self.options.no_color) return .standard;
        return self.options.color_system orelse self.terminal_info.color_system;
    }

    pub fn isTty(self: Console) bool {
        return self.options.force_terminal or self.terminal_info.is_tty;
    }

    fn getWriter(self: *Console) std.fs.File.Writer {
        return std.fs.File.stdout().writer(self.write_buffer);
    }

    pub fn print(self: *Console, text_markup: []const u8) !void {
        var txt = try Text.fromMarkup(self.allocator, text_markup);
        defer txt.deinit();
        try self.printText(txt);
        try self.writeLine();
    }

    pub fn printPlain(self: *Console, text: []const u8) !void {
        var writer = self.getWriter();
        try writer.interface.writeAll(text);
        try self.writeLine();
        try writer.interface.flush();
    }

    pub fn printStyled(self: *Console, text: []const u8, style: Style) !void {
        var writer = self.getWriter();
        try self.setStyle(style, &writer.interface);
        try writer.interface.writeAll(text);
        try self.resetStyle(&writer.interface);
        try self.writeLine();
        try writer.interface.flush();
    }

    pub fn printText(self: *Console, txt: Text) !void {
        const segments = try txt.render(self.allocator);
        defer self.allocator.free(segments);

        var writer = self.getWriter();
        for (segments) |seg| {
            try self.printSegment(seg, &writer.interface);
        }
        try writer.interface.flush();
    }

    pub fn printSegments(self: *Console, segments: []const Segment) !void {
        var writer = self.getWriter();
        for (segments) |seg| {
            try self.printSegment(seg, &writer.interface);
        }
        try writer.interface.flush();
    }

    fn printSegment(self: *Console, seg: Segment, writer: anytype) !void {
        if (seg.control) |ctrl| {
            try ctrl.toEscapeSequence(writer);
            return;
        }

        const has_style = if (seg.style) |s| !s.isEmpty() else false;
        if (has_style) {
            try self.setStyle(seg.style.?, writer);
        }

        try writer.writeAll(seg.text);

        if (self.capture_buffer) |*buf| {
            try buf.appendSlice(self.allocator, seg.text);
        }

        if (has_style) {
            try self.resetStyle(writer);
        }
        if (seg.style) |s| {
            if (s.link != null) {
                try Style.renderHyperlinkEnd(writer);
            }
        }
    }

    fn setStyle(self: *Console, style: Style, writer: anytype) !void {
        if (self.options.no_color) return;
        try style.renderAnsi(self.colorSystem(), writer);
        self.current_style = style;
    }

    fn resetStyle(self: *Console, writer: anytype) !void {
        if (self.options.no_color) return;
        try Style.renderReset(writer);
        self.current_style = Style.empty;
    }

    fn writeLine(self: *Console) !void {
        var writer = self.getWriter();
        try writer.interface.writeAll("\n");
        if (self.capture_buffer) |*buf| {
            try buf.append(self.allocator, '\n');
        }
    }

    pub fn rule(self: *Console, title_opt: ?[]const u8) !void {
        var writer = self.getWriter();
        const w = self.width();
        const char = "\u{2500}"; // horizontal line

        if (title_opt) |title| {
            const title_len = @import("cells.zig").cellLen(title);
            const total_rule_len = w - title_len - 2; // 2 for spaces around title
            const left_len = total_rule_len / 2;
            const right_len = total_rule_len - left_len;

            // Left side
            var i: usize = 0;
            while (i < left_len) : (i += 1) {
                try writer.interface.writeAll(char);
            }
            try writer.interface.writeAll(" ");
            try writer.interface.writeAll(title);
            try writer.interface.writeAll(" ");
            // Right side
            i = 0;
            while (i < right_len) : (i += 1) {
                try writer.interface.writeAll(char);
            }
        } else {
            var i: usize = 0;
            while (i < w) : (i += 1) {
                try writer.interface.writeAll(char);
            }
        }

        try writer.interface.writeAll("\n");
        try writer.interface.flush();
    }

    pub fn clear(self: *Console) !void {
        var writer = self.getWriter();
        try writer.interface.writeAll("\x1b[2J\x1b[H");
        try writer.interface.flush();
    }

    pub fn bell(self: *Console) !void {
        var writer = self.getWriter();
        try writer.interface.writeByte(0x07);
        try writer.interface.flush();
    }

    pub fn beginCapture(self: *Console) void {
        self.capture_buffer = std.ArrayList(u8).empty;
    }

    pub fn endCapture(self: *Console) ?[]const u8 {
        if (self.capture_buffer) |*buf| {
            const result = buf.toOwnedSlice(self.allocator) catch null;
            self.capture_buffer = null;
            return result;
        }
        return null;
    }

    pub fn exportText(segments: []const Segment, allocator: std.mem.Allocator) ![]u8 {
        return segment.joinText(segments, allocator);
    }

    pub fn exportCapture(self: *Console) ?[]u8 {
        const buf = self.capture_buffer orelse return null;
        return self.allocator.dupe(u8, buf.items) catch null;
    }

    pub fn setTitle(self: *Console, title: []const u8) !void {
        var writer = self.getWriter();
        try writer.interface.print("\x1b]0;{s}\x07", .{title});
        try writer.interface.flush();
    }

    fn writeEscapeSequence(self: *Console, sequence: []const u8) !void {
        var writer = self.getWriter();
        try writer.interface.writeAll(sequence);
        try writer.interface.flush();
    }

    pub fn showCursor(self: *Console) !void {
        try self.writeEscapeSequence("\x1b[?25h");
    }

    pub fn hideCursor(self: *Console) !void {
        try self.writeEscapeSequence("\x1b[?25l");
    }

    pub fn clearLine(self: *Console) !void {
        try self.writeEscapeSequence("\x1b[K");
    }

    pub fn enterAltScreen(self: *Console) !void {
        try self.writeEscapeSequence("\x1b[?1049h");
    }

    pub fn exitAltScreen(self: *Console) !void {
        try self.writeEscapeSequence("\x1b[?1049l");
    }

    pub fn log(self: *Console, level: LogLevel, comptime fmt: []const u8, args: anytype) !void {
        var writer = self.getWriter();

        // Get current time
        const timestamp = std.time.timestamp();
        const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const hours = day_seconds.getHoursIntoDay();
        const minutes = day_seconds.getMinutesIntoHour();
        const seconds = day_seconds.getSecondsIntoMinute();

        // Format: [HH:MM:SS] [LEVEL] message
        try writer.interface.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{ hours, minutes, seconds });

        // Level with styling
        const level_style = level.style();
        try self.setStyle(level_style, &writer.interface);
        try writer.interface.print("[{s}]", .{level.toString()});
        try self.resetStyle(&writer.interface);

        try writer.interface.writeAll(" ");

        // Message
        try writer.interface.print(fmt, args);
        try writer.interface.writeAll("\n");
        try writer.interface.flush();
    }

    pub fn logDebug(self: *Console, comptime fmt: []const u8, args: anytype) !void {
        try self.log(.debug, fmt, args);
    }

    pub fn logInfo(self: *Console, comptime fmt: []const u8, args: anytype) !void {
        try self.log(.info, fmt, args);
    }

    pub fn logWarn(self: *Console, comptime fmt: []const u8, args: anytype) !void {
        try self.log(.warn, fmt, args);
    }

    pub fn logErr(self: *Console, comptime fmt: []const u8, args: anytype) !void {
        try self.log(.err, fmt, args);
    }
};

// Tests
test "Console.init" {
    const allocator = std.testing.allocator;
    var console = Console.init(allocator);
    defer console.deinit();

    try std.testing.expect(console.width() > 0);
    try std.testing.expect(console.height() > 0);
}

test "Console.initWithOptions" {
    const allocator = std.testing.allocator;
    var console = Console.initWithOptions(allocator, .{
        .width = 120,
        .height = 40,
        .color_system = .truecolor,
    });
    defer console.deinit();

    try std.testing.expectEqual(@as(u16, 120), console.width());
    try std.testing.expectEqual(@as(u16, 40), console.height());
    try std.testing.expectEqual(ColorSystem.truecolor, console.colorSystem());
}

test "Console.no_color option" {
    const allocator = std.testing.allocator;
    var console = Console.initWithOptions(allocator, .{
        .no_color = true,
        .color_system = .truecolor,
    });
    defer console.deinit();

    try std.testing.expectEqual(ColorSystem.standard, console.colorSystem());
}

test "Console.exportText" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{
        Segment.plain("Hello"),
        Segment.plain(" "),
        Segment.plain("World"),
    };

    const text = try Console.exportText(&segments, allocator);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Hello World", text);
}

test "LogLevel.toString" {
    try std.testing.expectEqualStrings("DEBUG", LogLevel.debug.toString());
    try std.testing.expectEqualStrings("INFO", LogLevel.info.toString());
    try std.testing.expectEqualStrings("WARN", LogLevel.warn.toString());
    try std.testing.expectEqualStrings("ERROR", LogLevel.err.toString());
}

test "LogLevel.style" {
    const debug_style = LogLevel.debug.style();
    try std.testing.expect(debug_style.hasAttribute(.dim));

    const err_style = LogLevel.err.style();
    try std.testing.expect(err_style.color != null);
}

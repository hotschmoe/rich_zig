const std = @import("std");
const Style = @import("style.zig").Style;
const Color = @import("color.zig").Color;
const ColorSystem = @import("color.zig").ColorSystem;
const terminal = @import("terminal.zig");

/// Log level matching std.log.Level for compatibility
pub const Level = enum {
    debug,
    info,
    warn,
    err,

    pub fn toString(self: Level) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }

    pub fn toStdLevel(self: Level) std.log.Level {
        return switch (self) {
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
        };
    }

    pub fn fromStdLevel(level: std.log.Level) Level {
        return switch (level) {
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
        };
    }
};

/// Styles for each log level
pub const LevelStyles = struct {
    debug: Style = Style.empty.dim(),
    info: Style = Style.empty.foreground(Color.blue),
    warn: Style = Style.empty.foreground(Color.yellow).bold(),
    err: Style = Style.empty.foreground(Color.red).bold(),
    timestamp: Style = Style.empty.dim(),
    path: Style = Style.empty.foreground(Color.cyan).dim(),
    message: Style = Style.empty,

    pub const default: LevelStyles = .{};

    pub fn styleFor(self: LevelStyles, level: Level) Style {
        return switch (level) {
            .debug => self.debug,
            .info => self.info,
            .warn => self.warn,
            .err => self.err,
        };
    }
};

/// Format options for log output
pub const FormatOptions = struct {
    show_timestamp: bool = true,
    show_level: bool = true,
    show_path: bool = false,
    timestamp_format: TimestampFormat = .time_only,
    level_width: u8 = 5, // Width for level field (for alignment)
    path_width: ?u16 = null, // Max width for path, null for no limit

    pub const TimestampFormat = enum {
        time_only, // HH:MM:SS
        datetime, // YYYY-MM-DD HH:MM:SS
        iso8601, // YYYY-MM-DDTHH:MM:SSZ
    };
};

/// A log record with all metadata
pub const LogRecord = struct {
    level: Level,
    message: []const u8,
    timestamp: i64,
    path: ?[]const u8 = null,
    line: ?u32 = null,

    pub fn init(level: Level, message: []const u8) LogRecord {
        return .{
            .level = level,
            .message = message,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn withPath(self: LogRecord, path: []const u8) LogRecord {
        var r = self;
        r.path = path;
        return r;
    }

    pub fn withLine(self: LogRecord, line: u32) LogRecord {
        var r = self;
        r.line = line;
        return r;
    }
};

/// Rich-style log handler that formats and outputs log messages
pub const RichHandler = struct {
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    styles: LevelStyles,
    format: FormatOptions,
    color_system: ColorSystem,
    min_level: Level,
    write_buffer: []u8,

    const BUFFER_SIZE = 4096;

    pub fn init(allocator: std.mem.Allocator) RichHandler {
        return initWithOptions(allocator, .{}, .{});
    }

    pub fn initWithOptions(
        allocator: std.mem.Allocator,
        styles: LevelStyles,
        format: FormatOptions,
    ) RichHandler {
        const term_info = terminal.detect();
        const buffer = allocator.alloc(u8, BUFFER_SIZE) catch @panic("failed to allocate logging buffer");

        return .{
            .allocator = allocator,
            .writer = std.fs.File.stdout().writer(buffer),
            .styles = styles,
            .format = format,
            .color_system = term_info.color_system,
            .min_level = .debug,
            .write_buffer = buffer,
        };
    }

    pub fn deinit(self: *RichHandler) void {
        self.allocator.free(self.write_buffer);
    }

    pub fn setMinLevel(self: *RichHandler, level: Level) *RichHandler {
        self.min_level = level;
        return self;
    }

    pub fn setColorSystem(self: *RichHandler, color_system: ColorSystem) *RichHandler {
        self.color_system = color_system;
        return self;
    }

    pub fn emit(self: *RichHandler, record: LogRecord) !void {
        if (@intFromEnum(record.level) < @intFromEnum(self.min_level)) {
            return;
        }

        const writer = &self.writer.interface;

        // Timestamp
        if (self.format.show_timestamp) {
            try self.writeTimestamp(record.timestamp, writer);
            try writer.writeAll(" ");
        }

        // Level
        if (self.format.show_level) {
            try self.writeLevel(record.level, writer);
            try writer.writeAll(" ");
        }

        // Path
        if (self.format.show_path) {
            if (record.path) |path| {
                try self.writePath(path, record.line, writer);
                try writer.writeAll(" ");
            }
        }

        // Message
        try self.writeMessage(record.message, writer);
        try writer.writeByte('\n');
        try writer.flush();
    }

    fn writeTimestamp(self: *RichHandler, timestamp: i64, writer: anytype) !void {
        const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const hours = day_seconds.getHoursIntoDay();
        const minutes = day_seconds.getMinutesIntoHour();
        const seconds = day_seconds.getSecondsIntoMinute();

        try self.styles.timestamp.renderAnsi(self.color_system, writer);

        switch (self.format.timestamp_format) {
            .time_only => {
                try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });
            },
            .datetime, .iso8601 => {
                const year_day = epoch_seconds.getEpochDay().calculateYearDay();
                const year = year_day.year;
                const month_day = year_day.calculateMonthDay();
                const month = @intFromEnum(month_day.month) + 1;
                const day = month_day.day_index + 1;

                if (self.format.timestamp_format == .iso8601) {
                    try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
                        year, month, day, hours, minutes, seconds,
                    });
                } else {
                    try writer.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
                        year, month, day, hours, minutes, seconds,
                    });
                }
            },
        }

        try Style.renderReset(writer);
    }

    fn writeLevel(self: *RichHandler, level: Level, writer: anytype) !void {
        const level_str = level.toString();
        const level_style = self.styles.styleFor(level);

        try level_style.renderAnsi(self.color_system, writer);
        try writer.print("[{s}]", .{level_str});

        // Padding for alignment
        const written_len = level_str.len + 2; // +2 for brackets
        const target_width = self.format.level_width + 2;
        for (written_len..target_width) |_| try writer.writeByte(' ');

        try Style.renderReset(writer);
    }

    fn writePath(self: *RichHandler, path: []const u8, line: ?u32, writer: anytype) !void {
        try self.styles.path.renderAnsi(self.color_system, writer);

        // Truncate path if needed
        var display_path = path;
        if (self.format.path_width) |max_width| {
            if (path.len > max_width) {
                const start = path.len - max_width + 3; // +3 for "..."
                try writer.writeAll("...");
                display_path = path[start..];
            }
        }

        try writer.writeAll(display_path);

        if (line) |ln| {
            try writer.print(":{d}", .{ln});
        }

        try Style.renderReset(writer);
    }

    fn writeMessage(self: *RichHandler, message: []const u8, writer: anytype) !void {
        const styled = !self.styles.message.isEmpty();
        if (styled) try self.styles.message.renderAnsi(self.color_system, writer);
        try writer.writeAll(message);
        if (styled) try Style.renderReset(writer);
    }

    // Convenience methods
    pub fn debug(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(.debug, message));
    }

    pub fn info(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(.info, message));
    }

    pub fn warn(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(.warn, message));
    }

    pub fn err(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(.err, message));
    }
};

/// A formatted log function that can be used with std.log
/// Usage: pub const std_options = .{ .logFn = logging.stdLogFn };
pub fn stdLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // Get the global handler or use default styling
    const level_style = switch (level) {
        .debug => Style.empty.dim(),
        .info => Style.empty.foreground(Color.blue),
        .warn => Style.empty.foreground(Color.yellow).bold(),
        .err => Style.empty.foreground(Color.red).bold(),
    };
    const timestamp_style = Style.empty.dim();

    const scope_str = if (scope == .default) "" else @tagName(scope);

    // Format timestamp
    const timestamp = std.time.timestamp();
    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
    const day_seconds = epoch_seconds.getDaySeconds();

    const stderr = std.io.getStdErr().writer();

    // Write timestamp
    timestamp_style.renderAnsi(.truecolor, stderr) catch return;
    stderr.print("{d:0>2}:{d:0>2}:{d:0>2}", .{
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    }) catch return;
    Style.renderReset(stderr) catch return;
    stderr.writeAll(" ") catch return;

    // Write level
    level_style.renderAnsi(.truecolor, stderr) catch return;
    stderr.print("[{s}]", .{Level.fromStdLevel(level).toString()}) catch return;
    Style.renderReset(stderr) catch return;

    // Write scope if present
    if (scope_str.len > 0) {
        stderr.writeAll(" ") catch return;
        Style.empty.foreground(Color.cyan).dim().renderAnsi(.truecolor, stderr) catch return;
        stderr.print("({s})", .{scope_str}) catch return;
        Style.renderReset(stderr) catch return;
    }

    stderr.writeAll(" ") catch return;

    // Write message
    stderr.print(format, args) catch return;
    stderr.writeByte('\n') catch return;
}

/// Creates a scoped logger with Rich formatting
pub fn scopedLog(comptime scope: @TypeOf(.enum_literal)) type {
    return struct {
        pub fn debug(comptime format: []const u8, args: anytype) void {
            stdLogFn(.debug, scope, format, args);
        }

        pub fn info(comptime format: []const u8, args: anytype) void {
            stdLogFn(.info, scope, format, args);
        }

        pub fn warn(comptime format: []const u8, args: anytype) void {
            stdLogFn(.warn, scope, format, args);
        }

        pub fn err(comptime format: []const u8, args: anytype) void {
            stdLogFn(.err, scope, format, args);
        }
    };
}

// Tests
test "Level.toString" {
    try std.testing.expectEqualStrings("DEBUG", Level.debug.toString());
    try std.testing.expectEqualStrings("INFO", Level.info.toString());
    try std.testing.expectEqualStrings("WARN", Level.warn.toString());
    try std.testing.expectEqualStrings("ERROR", Level.err.toString());
}

test "Level.toStdLevel" {
    try std.testing.expectEqual(std.log.Level.debug, Level.debug.toStdLevel());
    try std.testing.expectEqual(std.log.Level.info, Level.info.toStdLevel());
    try std.testing.expectEqual(std.log.Level.warn, Level.warn.toStdLevel());
    try std.testing.expectEqual(std.log.Level.err, Level.err.toStdLevel());
}

test "Level.fromStdLevel" {
    try std.testing.expectEqual(Level.debug, Level.fromStdLevel(.debug));
    try std.testing.expectEqual(Level.info, Level.fromStdLevel(.info));
    try std.testing.expectEqual(Level.warn, Level.fromStdLevel(.warn));
    try std.testing.expectEqual(Level.err, Level.fromStdLevel(.err));
}

test "LevelStyles.styleFor" {
    const styles = LevelStyles.default;
    try std.testing.expect(styles.styleFor(.debug).hasAttribute(.dim));
    try std.testing.expect(styles.styleFor(.warn).hasAttribute(.bold));
    try std.testing.expect(styles.styleFor(.err).hasAttribute(.bold));
}

test "LogRecord.init" {
    const record = LogRecord.init(.info, "test message");
    try std.testing.expectEqual(Level.info, record.level);
    try std.testing.expectEqualStrings("test message", record.message);
    try std.testing.expect(record.timestamp > 0);
}

test "LogRecord.withPath" {
    const record = LogRecord.init(.debug, "msg").withPath("src/main.zig");
    try std.testing.expectEqualStrings("src/main.zig", record.path.?);
}

test "LogRecord.withLine" {
    const record = LogRecord.init(.debug, "msg").withLine(42);
    try std.testing.expectEqual(@as(u32, 42), record.line.?);
}

test "RichHandler.init" {
    const allocator = std.testing.allocator;
    var handler = RichHandler.init(allocator);
    defer handler.deinit();

    try std.testing.expectEqual(Level.debug, handler.min_level);
}

test "RichHandler.setMinLevel" {
    const allocator = std.testing.allocator;
    var handler = RichHandler.init(allocator);
    defer handler.deinit();

    _ = handler.setMinLevel(.warn);
    try std.testing.expectEqual(Level.warn, handler.min_level);
}

test "FormatOptions defaults" {
    const opts = FormatOptions{};
    try std.testing.expect(opts.show_timestamp);
    try std.testing.expect(opts.show_level);
    try std.testing.expect(!opts.show_path);
    try std.testing.expectEqual(FormatOptions.TimestampFormat.time_only, opts.timestamp_format);
}

test "scopedLog creates scoped logger" {
    const log = scopedLog(.mymodule);
    // Just verify it compiles - actual output goes to stderr
    _ = log;
}

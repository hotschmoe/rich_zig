const std = @import("std");
const Style = @import("style.zig").Style;
const Color = @import("color.zig").Color;
const ColorSystem = @import("color.zig").ColorSystem;
const terminal = @import("terminal.zig");
const Segment = @import("segment.zig").Segment;
const box = @import("box.zig");
const Panel = @import("renderables/panel.zig").Panel;
const Syntax = @import("renderables/syntax/mod.zig").Syntax;
const SyntaxTheme = @import("renderables/syntax/mod.zig").SyntaxTheme;
const Language = @import("renderables/syntax/mod.zig").Language;

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

pub const LogRecord = struct {
    level: Level,
    message: []const u8,
    timestamp: i64,
    path: ?[]const u8 = null,
    line: ?u32 = null,

    pub fn init(io: std.Io, level: Level, message: []const u8) LogRecord {
        return .{
            .level = level,
            .message = message,
            .timestamp = std.Io.Timestamp.now(io, .real).toSeconds(),
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

pub const RichHandler = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: std.Io.File.Writer,
    styles: LevelStyles,
    format: FormatOptions,
    color_system: ColorSystem,
    min_level: Level,
    write_buffer: []u8,

    const BUFFER_SIZE = 4096;

    pub fn init(io: std.Io, allocator: std.mem.Allocator, environ: std.process.Environ) RichHandler {
        return initWithOptions(io, allocator, environ, .{}, .{});
    }

    pub fn initWithOptions(
        io: std.Io,
        allocator: std.mem.Allocator,
        environ: std.process.Environ,
        styles: LevelStyles,
        format: FormatOptions,
    ) RichHandler {
        const term_info = terminal.detect(environ);
        const buffer = allocator.alloc(u8, BUFFER_SIZE) catch @panic("failed to allocate logging buffer");

        return .{
            .io = io,
            .allocator = allocator,
            .writer = std.Io.File.stdout().writer(io, buffer),
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
        if (@backingInt(record.level) < @backingInt(self.min_level)) {
            return;
        }

        const writer = &self.writer.interface;

        if (self.format.show_timestamp) {
            try self.writeTimestamp(record.timestamp, writer);
            try writer.writeAll(" ");
        }

        if (self.format.show_level) {
            try self.writeLevel(record.level, writer);
            try writer.writeAll(" ");
        }

        if (self.format.show_path) {
            if (record.path) |path| {
                try self.writePath(path, record.line, writer);
                try writer.writeAll(" ");
            }
        }

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
                const month = @backingInt(month_day.month) + 1;
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

        const written_len = level_str.len + 2; // +2 for brackets
        const target_width = self.format.level_width + 2;
        for (written_len..target_width) |_| try writer.writeByte(' ');

        try Style.renderReset(writer);
    }

    fn writePath(self: *RichHandler, path: []const u8, line: ?u32, writer: anytype) !void {
        try self.styles.path.renderAnsi(self.color_system, writer);

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

    pub fn debug(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(self.io, .debug, message));
    }

    pub fn info(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(self.io, .info, message));
    }

    pub fn warn(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(self.io, .warn, message));
    }

    pub fn err(self: *RichHandler, message: []const u8) !void {
        try self.emit(LogRecord.init(self.io, .err, message));
    }
};

pub fn stdLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_style = switch (level) {
        .debug => Style.empty.dim(),
        .info => Style.empty.foreground(Color.blue),
        .warn => Style.empty.foreground(Color.yellow).bold(),
        .err => Style.empty.foreground(Color.red).bold(),
    };
    const timestamp_style = Style.empty.dim();

    const scope_str = if (scope == .default) "" else @tagName(scope);

    var buf: [64]u8 = undefined;
    const locked = std.debug.lockStderr(&buf);
    defer std.debug.unlockStderr();
    const stderr = &locked.file_writer.interface;

    const timestamp = std.Io.Timestamp.now(std.Options.debug_io, .real).toSeconds();
    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
    const day_seconds = epoch_seconds.getDaySeconds();

    timestamp_style.renderAnsi(.truecolor, stderr) catch return;
    stderr.print("{d:0>2}:{d:0>2}:{d:0>2}", .{
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    }) catch return;
    Style.renderReset(stderr) catch return;
    stderr.writeAll(" ") catch return;

    level_style.renderAnsi(.truecolor, stderr) catch return;
    stderr.print("[{s}]", .{Level.fromStdLevel(level).toString()}) catch return;
    Style.renderReset(stderr) catch return;

    if (scope_str.len > 0) {
        stderr.writeAll(" ") catch return;
        Style.empty.foreground(Color.cyan).dim().renderAnsi(.truecolor, stderr) catch return;
        stderr.print("({s})", .{scope_str}) catch return;
        Style.renderReset(stderr) catch return;
    }

    stderr.writeAll(" ") catch return;

    stderr.print(format, args) catch return;
    stderr.writeByte('\n') catch return;
    stderr.flush() catch return;
}

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

pub const StackFrame = struct {
    file: ?[]const u8 = null,
    line: u32 = 0,
    column: u32 = 0,
    function: ?[]const u8 = null,
    address: ?usize = null,

    pub fn format(self: StackFrame, allocator: std.mem.Allocator) ![]u8 {
        var allocating: std.Io.Writer.Allocating = .init(allocator);
        defer allocating.deinit();
        const writer = &allocating.writer;

        if (self.function) |func| {
            try writer.writeAll(func);
        } else {
            try writer.writeAll("<unknown>");
        }

        if (self.file) |file| {
            try writer.print(" at {s}", .{file});
            if (self.line > 0) {
                try writer.print(":{d}", .{self.line});
                if (self.column > 0) {
                    try writer.print(":{d}", .{self.column});
                }
            }
        }

        if (self.address) |addr| {
            try writer.print(" (0x{x})", .{addr});
        }

        return allocating.toOwnedSlice();
    }
};

pub const TracebackTheme = struct {
    error_style: Style = Style.empty.foreground(Color.red).bold(),
    title_style: Style = Style.empty.bold(),
    file_style: Style = Style.empty.foreground(Color.cyan),
    line_number_style: Style = Style.empty.foreground(Color.yellow),
    function_style: Style = Style.empty.foreground(Color.green),
    highlight_style: Style = Style.empty.foreground(Color.red),
    frame_index_style: Style = Style.empty.dim(),
    context_style: Style = Style.empty.dim(),
    message_style: Style = Style.empty.foreground(Color.red),
    address_style: Style = Style.empty.dim(),

    pub const default: TracebackTheme = .{};

    pub const minimal: TracebackTheme = .{
        .error_style = Style.empty.foreground(Color.red),
        .title_style = Style.empty,
        .file_style = Style.empty,
        .line_number_style = Style.empty,
        .function_style = Style.empty,
        .highlight_style = Style.empty.bold(),
        .frame_index_style = Style.empty,
        .context_style = Style.empty,
        .message_style = Style.empty.foreground(Color.red),
        .address_style = Style.empty,
    };
};

pub const TracebackOptions = struct {
    context_before: u8 = 2,
    context_after: u8 = 2,
    show_line_numbers: bool = true,
    show_addresses: bool = false,
    show_box: bool = true,
    max_frames: u8 = 0,
    suppress_std: bool = false,
    show_source: bool = true,
    theme: TracebackTheme = TracebackTheme.default,
    syntax_highlighting: bool = true,
    syntax_theme: SyntaxTheme = SyntaxTheme.default,
};

pub const Traceback = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    message: ?[]const u8 = null,
    error_name: ?[]const u8 = null,
    frames: std.ArrayList(StackFrame),
    options: TracebackOptions = .{},
    source_cache: std.StringHashMap([]const []const u8),

    pub fn init(io: std.Io, allocator: std.mem.Allocator) Traceback {
        return .{
            .io = io,
            .allocator = allocator,
            .frames = std.ArrayList(StackFrame).empty,
            .source_cache = std.StringHashMap([]const []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Traceback) void {
        var it = self.source_cache.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*) |line| {
                self.allocator.free(line);
            }
            self.allocator.free(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.source_cache.deinit();
        self.frames.deinit(self.allocator);
    }

    pub fn withMessage(self: Traceback, msg: []const u8) Traceback {
        var t = self;
        t.message = msg;
        return t;
    }

    pub fn withErrorName(self: Traceback, name: []const u8) Traceback {
        var t = self;
        t.error_name = name;
        return t;
    }

    pub fn withOptions(self: Traceback, opts: TracebackOptions) Traceback {
        var t = self;
        t.options = opts;
        return t;
    }

    pub fn addFrame(self: *Traceback, frame: StackFrame) !void {
        try self.frames.append(self.allocator, frame);
    }

    pub fn captureCurrentTrace(self: *Traceback, skip_frames: usize) !void {
        var stack_trace = std.builtin.StackTrace{
            .instruction_addresses = undefined,
            .index = 0,
        };
        var addresses: [32]usize = undefined;
        stack_trace.instruction_addresses = &addresses;

        std.debug.captureStackTrace(@returnAddress(), &stack_trace);

        const debug_info = std.debug.getSelfDebugInfo() catch return;

        var frame_idx: usize = 0;
        for (stack_trace.instruction_addresses[0..stack_trace.index]) |addr| {
            if (addr == 0) break;

            if (frame_idx < skip_frames) {
                frame_idx += 1;
                continue;
            }

            var frame = StackFrame{ .address = addr };

            if (debug_info.getSymbolAtAddress(self.allocator, addr)) |symbol| {
                if (symbol.symbol_name) |name| {
                    frame.function = name;
                }
                if (symbol.source_location) |loc| {
                    frame.file = loc.file_name;
                    frame.line = @intCast(loc.line);
                    frame.column = @intCast(loc.column);
                }
            } else |_| {}

            try self.addFrame(frame);
            frame_idx += 1;
        }
    }

    pub fn parseZigTrace(self: *Traceback, trace_str: []const u8) !void {
        var lines = std.mem.splitScalar(u8, trace_str, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            if (parseZigFrameLine(trimmed)) |frame| {
                try self.addFrame(frame);
            }
        }
    }

    fn parseZigFrameLine(line: []const u8) ?StackFrame {

        var frame = StackFrame{};

        if (std.mem.startsWith(u8, line, "0x")) {
            const space_idx = std.mem.indexOfScalar(u8, line, ' ') orelse return null;
            frame.address = std.fmt.parseInt(usize, line[2..space_idx], 16) catch null;

            const rest = line[space_idx + 1 ..];
            if (std.mem.startsWith(u8, rest, "in ")) {
                const func_start = rest[3..];
                const paren_idx = std.mem.indexOfScalar(u8, func_start, '(');
                if (paren_idx) |idx| {
                    frame.function = std.mem.trim(u8, func_start[0..idx], " ");
                    const file_part = func_start[idx + 1 ..];
                    const close_paren = std.mem.indexOfScalar(u8, file_part, ')') orelse file_part.len;
                    const file_info = file_part[0..close_paren];
                    parseFileLocation(file_info, &frame);
                } else {
                    frame.function = func_start;
                }
            }
            return frame;
        }

        parseFileLocation(line, &frame);
        if (frame.file != null) {
            const in_idx = std.mem.indexOf(u8, line, " in ");
            if (in_idx) |idx| {
                frame.function = std.mem.trim(u8, line[idx + 4 ..], " ");
            }
            return frame;
        }

        return null;
    }

    fn parseFileLocation(text: []const u8, frame: *StackFrame) void {
        var parts = std.mem.splitScalar(u8, text, ':');
        const file_part = parts.next() orelse return;

        if (std.mem.indexOf(u8, file_part, ".") == null) return;

        frame.file = file_part;

        if (parts.next()) |line_str| {
            frame.line = std.fmt.parseInt(u32, line_str, 10) catch 0;

            if (parts.next()) |col_str| {
                frame.column = std.fmt.parseInt(u32, col_str, 10) catch 0;
            }
        }
    }

    fn getSourceLines(self: *Traceback, file_path: []const u8) ?[]const []const u8 {
        if (self.source_cache.get(file_path)) |lines| {
            return lines;
        }

        const file = std.Io.Dir.cwd().openFile(self.io, file_path, .{}) catch return null;
        defer file.close(self.io);

        var read_buf: [4096]u8 = undefined;
        var file_reader = file.reader(self.io, &read_buf);
        const content = file_reader.interface.allocRemaining(self.allocator, .limited64(1024 * 1024)) catch return null;
        defer self.allocator.free(content);

        var line_list: std.ArrayList([]const u8) = .empty;
        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            const duped = self.allocator.dupe(u8, line) catch return null;
            line_list.append(self.allocator, duped) catch {
                self.allocator.free(duped);
                return null;
            };
        }

        const lines = line_list.toOwnedSlice(self.allocator) catch return null;

        const key_copy = self.allocator.dupe(u8, file_path) catch {
            for (lines) |line| {
                self.allocator.free(line);
            }
            self.allocator.free(lines);
            return null;
        };
        self.source_cache.put(key_copy, lines) catch {
            self.allocator.free(key_copy);
            for (lines) |line| {
                self.allocator.free(line);
            }
            self.allocator.free(lines);
            return null;
        };

        return lines;
    }

    pub fn render(self: *Traceback, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;
        const theme = self.options.theme;

        const title = "Traceback (most recent call last):";
        const title_copy = try allocator.dupe(u8, title);
        try segments.append(allocator, Segment.styled(title_copy, theme.title_style));
        try segments.append(allocator, Segment.line());

        var frames_to_show = self.frames.items;
        if (self.options.max_frames > 0 and frames_to_show.len > self.options.max_frames) {
            frames_to_show = frames_to_show[0..self.options.max_frames];
        }

        // Frames are stored most recent first and rendered most recent last.
        var frame_idx: usize = frames_to_show.len;
        while (frame_idx > 0) {
            frame_idx -= 1;
            const frame = frames_to_show[frame_idx];

            if (self.options.suppress_std) {
                if (frame.file) |file| {
                    if (std.mem.indexOf(u8, file, "std/") != null) continue;
                }
            }

            try self.renderFrame(&segments, allocator, frame, frames_to_show.len - 1 - frame_idx);
        }

        if (self.error_name != null or self.message != null) {
            try segments.append(allocator, Segment.line());

            if (self.error_name) |name| {
                const name_copy = try allocator.dupe(u8, name);
                try segments.append(allocator, Segment.styled(name_copy, theme.error_style));
            }

            if (self.error_name != null and self.message != null) {
                const sep = try allocator.dupe(u8, ": ");
                try segments.append(allocator, Segment.styled(sep, theme.error_style));
            }

            if (self.message) |msg| {
                const msg_copy = try allocator.dupe(u8, msg);
                try segments.append(allocator, Segment.styled(msg_copy, theme.message_style));
            }
            try segments.append(allocator, Segment.line());
        }

        if (self.options.show_box) {
            const frame_segments = try segments.toOwnedSlice(allocator);

            var panel = Panel.fromSegments(allocator, frame_segments)
                .withBorderStyle(theme.error_style)
                .withTitle("Error")
                .withTitleStyle(theme.error_style);
            panel.box_style = box.BoxStyle.rounded;

            return panel.render(max_width, allocator);
        }

        return segments.toOwnedSlice(allocator);
    }

    fn renderFrame(
        self: *Traceback,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
        frame: StackFrame,
        index: usize,
    ) !void {
        const theme = self.options.theme;

        var idx_buf: [16]u8 = undefined;
        const idx_str = std.fmt.bufPrint(&idx_buf, "  #{d} ", .{index}) catch "  #? ";
        const idx_copy = try allocator.dupe(u8, idx_str);
        try segments.append(allocator, Segment.styled(idx_copy, theme.frame_index_style));

        if (frame.function) |func| {
            const func_copy = try allocator.dupe(u8, func);
            try segments.append(allocator, Segment.styled(func_copy, theme.function_style));
        } else {
            const unknown = try allocator.dupe(u8, "<unknown>");
            try segments.append(allocator, Segment.styled(unknown, theme.function_style));
        }

        try segments.append(allocator, Segment.line());

        if (frame.file) |file| {
            const indent = try allocator.dupe(u8, "     ");
            try segments.append(allocator, Segment.plain(indent));

            const file_copy = try allocator.dupe(u8, file);
            try segments.append(allocator, Segment.styled(file_copy, theme.file_style));

            if (frame.line > 0) {
                const colon = try allocator.dupe(u8, ":");
                try segments.append(allocator, Segment.plain(colon));

                var line_buf: [16]u8 = undefined;
                const line_str = std.fmt.bufPrint(&line_buf, "{d}", .{frame.line}) catch "?";
                const line_copy = try allocator.dupe(u8, line_str);
                try segments.append(allocator, Segment.styled(line_copy, theme.line_number_style));

                if (frame.column > 0) {
                    const colon2 = try allocator.dupe(u8, ":");
                    try segments.append(allocator, Segment.plain(colon2));

                    var col_buf: [16]u8 = undefined;
                    const col_str = std.fmt.bufPrint(&col_buf, "{d}", .{frame.column}) catch "?";
                    const col_copy = try allocator.dupe(u8, col_str);
                    try segments.append(allocator, Segment.styled(col_copy, theme.line_number_style));
                }
            }

            if (self.options.show_addresses) {
                if (frame.address) |addr| {
                    var addr_buf: [32]u8 = undefined;
                    const addr_str = std.fmt.bufPrint(&addr_buf, " (0x{x})", .{addr}) catch "";
                    const addr_copy = try allocator.dupe(u8, addr_str);
                    try segments.append(allocator, Segment.styled(addr_copy, theme.address_style));
                }
            }

            try segments.append(allocator, Segment.line());

            if (self.options.show_source and frame.line > 0) {
                try self.renderSourceContext(segments, allocator, frame);
            }
        }
    }

    fn renderSourceContext(
        self: *Traceback,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
        frame: StackFrame,
    ) !void {
        const theme = self.options.theme;

        const file_path = frame.file orelse return;
        const source_lines = self.getSourceLines(file_path) orelse return;

        const target_line = frame.line;
        if (target_line == 0 or target_line > source_lines.len) return;

        const start_line = if (target_line > self.options.context_before)
            target_line - self.options.context_before
        else
            1;
        const end_line = @min(target_line + self.options.context_after, @as(u32, @intCast(source_lines.len)));

        const language = if (self.options.syntax_highlighting)
            Language.fromFilename(file_path)
        else
            Language.plain;

        var line_num = start_line;
        while (line_num <= end_line) : (line_num += 1) {
            const line_content = source_lines[line_num - 1];
            const is_target = (line_num == target_line);

            const marker: []const u8 = if (is_target) " > " else "   ";
            const marker_copy = try allocator.dupe(u8, marker);
            const marker_style = if (is_target) theme.highlight_style else theme.context_style;
            try segments.append(allocator, Segment.styled(marker_copy, marker_style));

            if (self.options.show_line_numbers) {
                var line_buf: [16]u8 = undefined;
                const line_str = std.fmt.bufPrint(&line_buf, "{d:>4} | ", .{line_num}) catch "   ? | ";
                const line_copy = try allocator.dupe(u8, line_str);
                try segments.append(allocator, Segment.styled(line_copy, theme.line_number_style));
            }

            if (self.options.syntax_highlighting and language != .plain) {
                const highlighted_segments = try self.highlightSourceLine(
                    allocator,
                    line_content,
                    language,
                );
                defer allocator.free(highlighted_segments);

                for (highlighted_segments) |seg| {
                    if (std.mem.eql(u8, seg.text, "\n")) continue;
                    if (seg.text.len == 0) continue;

                    const text_copy = try allocator.dupe(u8, seg.text);
                    const style = if (is_target)
                        blendHighlightStyle(seg.style, theme.highlight_style)
                    else
                        seg.style orelse Style.empty;
                    try segments.append(allocator, Segment.styled(text_copy, style));
                }
            } else {
                const line_copy = try allocator.dupe(u8, line_content);
                const content_style = if (is_target) theme.highlight_style else theme.context_style;
                try segments.append(allocator, Segment.styled(line_copy, content_style));
            }
            try segments.append(allocator, Segment.line());

            if (is_target and frame.column > 0) {
                const prefix_len: usize = 3 + (if (self.options.show_line_numbers) @as(usize, 8) else 0);
                const total_indent = prefix_len + frame.column - 1;

                const indent_str = try allocator.alloc(u8, total_indent);
                @memset(indent_str, ' ');
                try segments.append(allocator, Segment.plain(indent_str));

                const caret = try allocator.dupe(u8, "^");
                try segments.append(allocator, Segment.styled(caret, theme.highlight_style));
                try segments.append(allocator, Segment.line());
            }
        }
    }

    fn highlightSourceLine(
        self: *Traceback,
        allocator: std.mem.Allocator,
        line: []const u8,
        language: Language,
    ) ![]Segment {
        const syntax = Syntax.init(allocator, line)
            .withLanguage(language)
            .withTheme(self.options.syntax_theme);

        return syntax.render(0, allocator);
    }
};

fn blendHighlightStyle(syntax_style: ?Style, highlight_style: Style) Style {
    var result = syntax_style orelse Style.empty;

    if (highlight_style.hasAttribute(.bold)) {
        result = result.bold();
    }
    if (highlight_style.hasAttribute(.underline)) {
        result = result.underline();
    }
    if (highlight_style.bgcolor != null and result.bgcolor == null) {
        result = result.background(highlight_style.bgcolor.?);
    }

    return result;
}

pub fn traceHere(io: std.Io, allocator: std.mem.Allocator) !Traceback {
    var tb = Traceback.init(io, allocator);
    try tb.captureCurrentTrace(1); // Skip this function
    return tb;
}

pub fn traceError(io: std.Io, allocator: std.mem.Allocator, err: anyerror) !Traceback {
    var tb = Traceback.init(io, allocator);
    tb.error_name = @errorName(err);
    try tb.captureCurrentTrace(1);
    return tb;
}

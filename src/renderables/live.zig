const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Console = @import("../console.zig").Console;

pub const Live = struct {
    console: *Console,
    min_refresh_ms: u64 = 50,
    last_refresh_time: i64 = 0,
    lines_rendered: usize = 0,
    is_started: bool = false,

    pub fn init(console: *Console) Live {
        return .{
            .console = console,
        };
    }

    pub fn withRefreshRate(self: Live, ms: u64) Live {
        var l = self;
        l.min_refresh_ms = ms;
        return l;
    }

    pub fn start(self: *Live) !void {
        if (self.is_started) return;
        try self.console.hideCursor();
        self.is_started = true;
        self.lines_rendered = 0;
    }

    pub fn stop(self: *Live) !void {
        if (!self.is_started) return;
        try self.console.showCursor();
        self.is_started = false;
    }

    pub fn update(self: *Live, segments: []const Segment) !void {
        if (!self.is_started) return;

        const now = std.time.milliTimestamp();
        if (now - self.last_refresh_time < @as(i64, @intCast(self.min_refresh_ms))) {
            return;
        }
        self.last_refresh_time = now;

        try self.renderSegments(segments);
    }

    pub fn forceUpdate(self: *Live, segments: []const Segment) !void {
        if (!self.is_started) return;

        try self.renderSegments(segments);
        self.last_refresh_time = std.time.milliTimestamp();
    }

    fn renderSegments(self: *Live, segments: []const Segment) !void {
        try self.clearPrevious();

        var line_count: usize = 1;
        for (segments) |seg| {
            if (std.mem.eql(u8, seg.text, "\n")) {
                line_count += 1;
            }
        }

        try self.console.printSegments(segments);
        self.lines_rendered = line_count;
    }

    fn clearPrevious(self: *Live) !void {
        if (self.lines_rendered == 0) return;

        const stdout = std.fs.File.stdout();
        var writer = stdout.writer(self.console.write_buffer);

        for (0..self.lines_rendered) |_| {
            try writer.interface.writeAll("\x1b[A");
            try writer.interface.writeAll("\x1b[2K");
        }
        try writer.interface.writeAll("\r");
        try writer.interface.flush();
    }

    pub fn shouldRefresh(self: Live) bool {
        const now = std.time.milliTimestamp();
        return now - self.last_refresh_time >= @as(i64, @intCast(self.min_refresh_ms));
    }
};

test "Live.init" {
    const allocator = std.testing.allocator;
    var console = Console.init(allocator);
    defer console.deinit();

    const live = Live.init(&console);
    try std.testing.expectEqual(@as(u64, 50), live.min_refresh_ms);
    try std.testing.expect(!live.is_started);
}

test "Live.withRefreshRate" {
    const allocator = std.testing.allocator;
    var console = Console.init(allocator);
    defer console.deinit();

    const live = Live.init(&console).withRefreshRate(100);
    try std.testing.expectEqual(@as(u64, 100), live.min_refresh_ms);
}

test "Live.start sets is_started" {
    const allocator = std.testing.allocator;
    var console = Console.init(allocator);
    defer console.deinit();

    var live = Live.init(&console);
    live.is_started = true;
    try std.testing.expect(live.is_started);
    live.is_started = false;
    try std.testing.expect(!live.is_started);
}

test "Live.update without start" {
    const allocator = std.testing.allocator;
    var console = Console.init(allocator);
    defer console.deinit();

    var live = Live.init(&console);
    const segments = [_]Segment{Segment.plain("test")};

    try live.update(&segments);
    try std.testing.expectEqual(@as(usize, 0), live.lines_rendered);
}

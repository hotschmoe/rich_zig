const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const segment_mod = @import("../segment.zig");
const Console = @import("../console.zig").Console;
const assert = @import("assert").assert;
const host_mod = @import("../host.zig");

pub const OverflowMode = enum {
    visible,
    clip,
    scroll,
};

pub const wait_rounds_extra: u64 = 3;

pub fn is_due(last_ms: ?i64, at_ms: i64, interval_ms: u64) bool {
    const last = last_ms orelse return true;
    if (at_ms < last) return true;
    const elapsed: u64 = @intCast(at_ms -| last);
    assert(at_ms >= last);
    assert(elapsed <= std.math.maxInt(i64));
    return elapsed >= interval_ms;
}

pub fn now_ms(host: host_mod.Host) i64 {
    return @divFloor(host.now(.monotonic), std.time.ns_per_ms);
}

pub fn wait_loop(host: host_mod.Host, duration_ms: u64, interval_ms: u64, target: anytype) !void {
    const interval = @max(interval_ms, 1);
    const rounds_max = duration_ms / interval + wait_rounds_extra;
    const begin = now_ms(host);
    var rounds: u64 = 0;
    while (rounds < rounds_max) : (rounds += 1) {
        const now = now_ms(host);
        _ = try target.tick(now);
        const elapsed: u64 = if (now > begin) @intCast(now - begin) else 0;
        if (elapsed >= duration_ms) return;
        const step_ms = @min(duration_ms - elapsed, interval);
        assert(step_ms > 0);
        assert(rounds < rounds_max);
        try host.wait(step_ms * std.time.ns_per_ms);
    }
}

pub const Live = struct {
    console: *Console,
    min_refresh_ms: u64 = 50,
    last_refresh_time: ?i64 = null,
    lines_rendered: usize = 0,
    is_started: bool = false,
    overflow_mode: OverflowMode = .visible,
    max_lines: ?usize = null,
    scroll_offset: usize = 0,
    content: ?[]const Segment = null,

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

    pub fn withOverflow(self: Live, mode: OverflowMode) Live {
        var l = self;
        l.overflow_mode = mode;
        return l;
    }

    pub fn withMaxLines(self: Live, lines: ?usize) Live {
        var l = self;
        l.max_lines = lines;
        return l;
    }

    pub fn scrollUp(self: *Live, lines: usize) void {
        self.scroll_offset -|= lines;
    }

    pub fn scrollDown(self: *Live, lines: usize) void {
        self.scroll_offset +|= lines;
    }

    pub fn scrollToTop(self: *Live) void {
        self.scroll_offset = 0;
    }

    pub fn scrollToBottom(self: *Live, total_lines: usize) void {
        if (self.max_lines) |max| {
            if (total_lines > max) {
                self.scroll_offset = total_lines - max;
            }
        }
    }

    pub fn start(self: *Live) !void {
        if (self.is_started) return;
        try self.console.hideCursor();
        self.is_started = true;
        self.lines_rendered = 0;
        self.last_refresh_time = null;
        assert(self.is_started);
        assert(self.lines_rendered == 0);
    }

    pub fn stop(self: *Live) !void {
        if (!self.is_started) return;
        self.is_started = false;
        try self.console.showCursor();
        assert(!self.is_started);
    }

    pub fn setContent(self: *Live, segments: []const Segment) void {
        self.content = segments;
    }

    pub fn tick(self: *Live, at_ms: i64) !bool {
        if (!self.is_started) return false;
        const segments = self.content orelse return false;
        if (!is_due(self.last_refresh_time, at_ms, self.min_refresh_ms)) return false;
        self.last_refresh_time = at_ms;
        try self.renderSegments(segments);
        assert(self.last_refresh_time.? == at_ms);
        assert(self.is_started);
        return true;
    }

    pub fn wait(self: *Live, duration_ms: u64) !void {
        try wait_loop(self.console.host(), duration_ms, self.min_refresh_ms, self);
    }

    pub fn update(self: *Live, segments: []const Segment) !void {
        if (!self.is_started) return;

        const now = now_ms(self.console.host());
        if (!is_due(self.last_refresh_time, now, self.min_refresh_ms)) return;
        self.last_refresh_time = now;
        assert(self.is_started);

        try self.renderSegments(segments);
        assert(self.last_refresh_time.? == now);
    }

    pub fn forceUpdate(self: *Live, segments: []const Segment) !void {
        if (!self.is_started) return;

        assert(self.is_started);
        try self.renderSegments(segments);
        self.last_refresh_time = now_ms(self.console.host());
    }

    fn renderSegments(self: *Live, segments: []const Segment) !void {
        try self.clearPrevious();

        var total_lines: usize = 1;
        for (segments) |seg| {
            if (std.mem.eql(u8, seg.text, "\n")) {
                total_lines += 1;
            }
        }

        const max = self.max_lines orelse total_lines;

        if (self.overflow_mode == .visible or total_lines <= max) {
            try self.console.printSegments(segments);
            self.lines_rendered = total_lines;
            return;
        }

        switch (self.overflow_mode) {
            .clip => {
                var line_count: usize = 0;
                for (segments) |seg| {
                    if (line_count >= max) break;
                    if (std.mem.eql(u8, seg.text, "\n")) {
                        line_count += 1;
                        if (line_count < max) {
                            try self.console.printSegments(&[_]Segment{seg});
                        }
                    } else {
                        try self.console.printSegments(&[_]Segment{seg});
                    }
                }
                try self.console.printSegments(&[_]Segment{Segment.line()});
                self.lines_rendered = @min(max, total_lines);
            },
            .scroll => {
                const scroll = @min(self.scroll_offset, if (total_lines > max) total_lines - max else 0);
                var line_count: usize = 0;
                var visible_lines: usize = 0;

                for (segments) |seg| {
                    if (line_count >= scroll and visible_lines < max) {
                        if (std.mem.eql(u8, seg.text, "\n")) {
                            visible_lines += 1;
                            if (visible_lines < max) {
                                try self.console.printSegments(&[_]Segment{seg});
                            }
                        } else {
                            try self.console.printSegments(&[_]Segment{seg});
                        }
                    }
                    if (std.mem.eql(u8, seg.text, "\n")) {
                        line_count += 1;
                    }
                }
                try self.console.printSegments(&[_]Segment{Segment.line()});
                self.lines_rendered = visible_lines;
            },
            .visible => unreachable,
        }
    }

    fn clearPrevious(self: *Live) !void {
        if (self.lines_rendered == 0) return;
        try self.console.erase_lines(self.lines_rendered);
    }

    pub fn shouldRefresh(self: *Live) bool {
        return is_due(self.last_refresh_time, now_ms(self.console.host()), self.min_refresh_ms);
    }
};

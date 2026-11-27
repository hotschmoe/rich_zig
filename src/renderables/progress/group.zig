const std = @import("std");
const Segment = @import("../../segment.zig").Segment;
const Style = @import("../../style.zig").Style;
const Color = @import("../../color.zig").Color;
const ProgressBar = @import("bar.zig").ProgressBar;
const host_mod = @import("../../host.zig");
const assert = @import("assert").assert;
const live_mod = @import("../live.zig");
const Live = live_mod.Live;

pub const ProgressGroup = struct {
    bars: std.ArrayList(ProgressBar),
    allocator: std.mem.Allocator,
    source: host_mod.Source,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) ProgressGroup {
        return .{
            .bars = std.ArrayList(ProgressBar).empty,
            .allocator = allocator,
            .source = host_mod.Source.from_io(io, .empty),
        };
    }

    pub fn initWithHost(allocator: std.mem.Allocator, bound: host_mod.Host) ProgressGroup {
        return .{
            .bars = std.ArrayList(ProgressBar).empty,
            .allocator = allocator,
            .source = .{ .custom = bound },
        };
    }

    fn new_bar(self: ProgressGroup) ProgressBar {
        return .{ .source = self.source };
    }

    pub fn deinit(self: *ProgressGroup) void {
        self.bars.deinit(self.allocator);
    }

    pub fn addTask(self: *ProgressGroup, description: []const u8, total: usize) !*ProgressBar {
        try self.bars.append(self.allocator, self.new_bar()
            .withDescription(description)
            .withTotal(total));
        return &self.bars.items[self.bars.items.len - 1];
    }

    pub fn addTaskWithTiming(self: *ProgressGroup, description: []const u8, total: usize) !*ProgressBar {
        try self.bars.append(self.allocator, self.new_bar()
            .withDescription(description)
            .withTotal(total)
            .withTiming());
        return &self.bars.items[self.bars.items.len - 1];
    }

    pub fn addBar(self: *ProgressGroup, bar: ProgressBar) !*ProgressBar {
        try self.bars.append(self.allocator, bar);
        return &self.bars.items[self.bars.items.len - 1];
    }

    pub fn render(self: ProgressGroup, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        for (self.bars.items, 0..) |bar, i| {
            if (bar.shouldHide()) continue;

            const bar_segments = try bar.render(max_width, allocator);
            defer allocator.free(bar_segments);

            for (bar_segments) |seg| {
                try segments.append(allocator, seg);
            }

            if (i < self.bars.items.len - 1) {
                try segments.append(allocator, Segment.line());
            }
        }

        return segments.toOwnedSlice(allocator);
    }

    pub fn allFinished(self: ProgressGroup) bool {
        for (self.bars.items) |bar| {
            if (!bar.isFinished()) return false;
        }
        return true;
    }

    pub fn visibleCount(self: ProgressGroup) usize {
        var count: usize = 0;
        for (self.bars.items) |bar| {
            if (!bar.shouldHide()) count += 1;
        }
        return count;
    }
};

pub const ProgressDisplay = struct {
    group: *ProgressGroup,
    live: ?*Live = null,
    refresh_ms: u64 = 100,
    allocator: std.mem.Allocator,
    source: host_mod.Source,
    last_tick_ms: ?i64 = null,
    is_running: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, group: *ProgressGroup) ProgressDisplay {
        return .{
            .group = group,
            .allocator = allocator,
            .source = host_mod.Source.from_io(io, .empty),
        };
    }

    pub fn initWithHost(
        allocator: std.mem.Allocator,
        bound: host_mod.Host,
        group: *ProgressGroup,
    ) ProgressDisplay {
        return .{ .group = group, .allocator = allocator, .source = .{ .custom = bound } };
    }

    pub fn withRefreshRate(self: ProgressDisplay, ms: u64) ProgressDisplay {
        var pd = self;
        pd.refresh_ms = ms;
        return pd;
    }

    pub fn withLive(self: ProgressDisplay, live: *Live) ProgressDisplay {
        var pd = self;
        pd.live = live;
        return pd;
    }

    pub fn start(self: *ProgressDisplay) !void {
        if (self.is_running) return;
        if (self.live) |live| try live.start();
        self.is_running = true;
        self.last_tick_ms = null;
        assert(self.is_running);
        assert(self.live == null or self.live.?.is_started);
    }

    pub fn stop(self: *ProgressDisplay) !void {
        if (!self.is_running) return;
        self.is_running = false;
        if (self.live) |live| try live.stop();
        assert(!self.is_running);
        assert(self.live == null or !self.live.?.is_started);
    }

    pub fn tick(self: *ProgressDisplay, at_ms: i64) !bool {
        if (!self.is_running) return false;
        const live = self.live orelse return false;
        if (!live_mod.is_due(self.last_tick_ms, at_ms, self.refresh_ms)) return false;
        self.last_tick_ms = at_ms;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const segments = try self.group.render(live.console.width(), arena.allocator());
        assert(live.is_started);
        try live.forceUpdate(segments);
        assert(self.last_tick_ms.? == at_ms);
        return true;
    }

    pub fn wait(self: *ProgressDisplay, duration_ms: u64) !void {
        try live_mod.wait_loop(self.source.host(), duration_ms, self.refresh_ms, self);
    }

    pub fn advanceSpinners(self: *ProgressDisplay) void {
        for (self.group.bars.items) |*bar| {
            if (bar.indeterminate) {
                bar.advancePulse();
            }
        }
    }
};

pub const ColumnRenderContext = struct {
    completed: usize,
    total: usize,
    percentage: f64,
    elapsed_seconds: u64,
    eta_seconds: ?u64,
    speed: f64,
    description: ?[]const u8,
    is_finished: bool,
    is_indeterminate: bool,
    current_ms: i64 = 0,
};

pub const ColumnWidth = union(enum) {
    fixed: usize,
    ratio: usize,
    auto,
};

pub const BuiltinColumn = enum {
    description,
    bar,
    percentage,
    elapsed,
    eta,
    speed,
    spinner,
    completed,
    total,
    task_count,

    pub fn defaultWidth(self: BuiltinColumn) ColumnWidth {
        return switch (self) {
            .description => .auto,
            .bar => .{ .ratio = 1 },
            .percentage => .{ .fixed = 5 },
            .elapsed => .{ .fixed = 8 },
            .eta => .{ .fixed = 12 },
            .speed => .{ .fixed = 12 },
            .spinner => .{ .fixed = 2 },
            .completed => .{ .fixed = 8 },
            .total => .{ .fixed = 8 },
            .task_count => .{ .fixed = 10 },
        };
    }
};

pub const CustomColumnFn = *const fn (ctx: ColumnRenderContext, allocator: std.mem.Allocator) anyerror![]Segment;

pub const ProgressColumn = struct {
    column_type: ColumnType,
    width: ColumnWidth = .auto,
    style: Style = Style.empty,
    min_width: ?usize = null,
    max_width: ?usize = null,
    visible: bool = true,

    pub const ColumnType = union(enum) {
        builtin: BuiltinColumn,
        custom: CustomColumnFn,
        text: []const u8,
    };

    pub fn builtin(col: BuiltinColumn) ProgressColumn {
        return .{
            .column_type = .{ .builtin = col },
            .width = col.defaultWidth(),
        };
    }

    pub fn custom(render_fn: CustomColumnFn) ProgressColumn {
        return .{
            .column_type = .{ .custom = render_fn },
        };
    }

    pub fn text(content: []const u8) ProgressColumn {
        return .{
            .column_type = .{ .text = content },
        };
    }

    pub fn withWidth(self: ProgressColumn, w: ColumnWidth) ProgressColumn {
        var col = self;
        col.width = w;
        return col;
    }

    pub fn withFixedWidth(self: ProgressColumn, w: usize) ProgressColumn {
        var col = self;
        col.width = .{ .fixed = w };
        return col;
    }

    pub fn withRatio(self: ProgressColumn, r: usize) ProgressColumn {
        var col = self;
        col.width = .{ .ratio = r };
        return col;
    }

    pub fn withStyle(self: ProgressColumn, s: Style) ProgressColumn {
        var col = self;
        col.style = s;
        return col;
    }

    pub fn withMinWidth(self: ProgressColumn, w: usize) ProgressColumn {
        var col = self;
        col.min_width = w;
        return col;
    }

    pub fn withMaxWidth(self: ProgressColumn, w: usize) ProgressColumn {
        var col = self;
        col.max_width = w;
        return col;
    }

    pub fn hidden(self: ProgressColumn) ProgressColumn {
        var col = self;
        col.visible = false;
        return col;
    }

    pub fn render(self: ProgressColumn, ctx: ColumnRenderContext, bar_width: usize, allocator: std.mem.Allocator) ![]Segment {
        if (!self.visible) {
            return &.{};
        }

        switch (self.column_type) {
            .builtin => |b| return try self.renderBuiltin(b, ctx, bar_width, allocator),
            .custom => |func| {
                const segments = try func(ctx, allocator);
                self.applyStyle(segments);
                return segments;
            },
            .text => |content| {
                const result = try allocator.alloc(Segment, 1);
                result[0] = self.styledSegment(content);
                return result;
            },
        }
    }

    fn styledSegment(self: ProgressColumn, content: []const u8) Segment {
        return if (self.style.isEmpty()) Segment.plain(content) else Segment.styled(content, self.style);
    }

    fn applyStyle(self: ProgressColumn, segments: []Segment) void {
        if (self.style.isEmpty()) return;

        for (segments) |*seg| {
            if (seg.style) |existing| {
                seg.style = existing.combine(self.style);
            } else {
                seg.style = self.style;
            }
        }
    }

    fn renderBuiltin(self: ProgressColumn, col: BuiltinColumn, ctx: ColumnRenderContext, bar_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        switch (col) {
            .description => {
                if (ctx.description) |desc| {
                    try segments.append(allocator, self.styledSegment(desc));
                }
            },
            .bar => {
                const style = if (ctx.is_finished)
                    Style.empty.foreground(Color.bright_green)
                else
                    Style.empty.foreground(Color.green);
                const incomplete_style = Style.empty.dim();

                if (ctx.is_indeterminate) {
                    for (0..bar_width) |_| {
                        try segments.append(allocator, Segment.styled("\u{2501}", incomplete_style));
                    }
                } else {
                    const ratio: f64 = ctx.percentage / 100.0;
                    const complete_width: usize = @intFromFloat(@min(ratio, 1.0) * @as(f64, @floatFromInt(bar_width)));
                    const incomplete_width = bar_width - complete_width;

                    for (0..complete_width) |_| {
                        try segments.append(allocator, Segment.styled("\u{2501}", style));
                    }
                    for (0..incomplete_width) |_| {
                        try segments.append(allocator, Segment.styled("\u{2501}", incomplete_style));
                    }
                }
            },
            .percentage => {
                const pct_str = @import("bar.zig").getPercentageString(ctx.percentage);
                try segments.append(allocator, self.styledSegment(pct_str));
            },
            .elapsed => {
                var buf: [12]u8 = undefined;
                const time_str = ProgressBar.formatTime(ctx.elapsed_seconds, &buf);
                try segments.append(allocator, self.styledSegment(try allocator.dupe(u8, time_str)));
            },
            .eta => {
                if (ctx.eta_seconds) |eta| {
                    var buf: [16]u8 = undefined;
                    const eta_str = ProgressBar.formatTime(eta, &buf);
                    try segments.append(allocator, Segment.plain("ETA "));
                    try segments.append(allocator, self.styledSegment(try allocator.dupe(u8, eta_str)));
                } else {
                    try segments.append(allocator, Segment.plain("--:--"));
                }
            },
            .speed => {
                var buf: [24]u8 = undefined;
                const speed_str = ProgressBar.formatSpeed(ctx.speed, .items, "it/s", &buf);
                try segments.append(allocator, self.styledSegment(try allocator.dupe(u8, speed_str)));
            },
            .spinner => {
                const frames = [_][]const u8{
                    "\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}",
                    "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}",
                };
                const frame_idx = @as(usize, @intCast(@mod(@divFloor(ctx.current_ms, 100), @as(i64, frames.len))));
                try segments.append(allocator, self.styledSegment(frames[frame_idx]));
            },
            .completed => {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{ctx.completed}) catch "?";
                try segments.append(allocator, self.styledSegment(try allocator.dupe(u8, str)));
            },
            .total => {
                var buf: [16]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{ctx.total}) catch "?";
                try segments.append(allocator, self.styledSegment(try allocator.dupe(u8, str)));
            },
            .task_count => {
                var buf: [24]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}/{d}", .{ ctx.completed, ctx.total }) catch "?/?";
                try segments.append(allocator, self.styledSegment(try allocator.dupe(u8, str)));
            },
        }

        return segments.toOwnedSlice(allocator);
    }
};

pub const Progress = struct {
    columns: std.ArrayList(ProgressColumn),
    completed: usize = 0,
    total: usize = 100,
    description: ?[]const u8 = null,
    start_time: ?i64 = null,
    indeterminate: bool = false,
    separator: []const u8 = " ",
    allocator: std.mem.Allocator,
    source: host_mod.Source,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Progress {
        return .{
            .columns = std.ArrayList(ProgressColumn).empty,
            .allocator = allocator,
            .source = host_mod.Source.from_io(io, .empty),
        };
    }

    pub fn initWithHost(allocator: std.mem.Allocator, bound: host_mod.Host) Progress {
        return .{
            .columns = std.ArrayList(ProgressColumn).empty,
            .allocator = allocator,
            .source = .{ .custom = bound },
        };
    }

    pub fn deinit(self: *Progress) void {
        self.columns.deinit(self.allocator);
    }

    pub fn withDefaultColumns(allocator: std.mem.Allocator, io: std.Io) !Progress {
        var p = Progress.init(allocator, io);
        try p.addColumn(ProgressColumn.builtin(.description));
        try p.addColumn(ProgressColumn.builtin(.bar));
        try p.addColumn(ProgressColumn.builtin(.percentage));
        return p;
    }

    pub fn withDownloadColumns(allocator: std.mem.Allocator, io: std.Io) !Progress {
        var p = Progress.init(allocator, io);
        try p.addColumn(ProgressColumn.builtin(.description));
        try p.addColumn(ProgressColumn.builtin(.bar));
        try p.addColumn(ProgressColumn.builtin(.percentage));
        try p.addColumn(ProgressColumn.builtin(.elapsed));
        try p.addColumn(ProgressColumn.builtin(.speed));
        try p.addColumn(ProgressColumn.builtin(.eta));
        return p;
    }

    pub fn addColumn(self: *Progress, column: ProgressColumn) !void {
        try self.columns.append(self.allocator, column);
    }

    pub fn addCustomColumn(self: *Progress, render_fn: CustomColumnFn) !void {
        try self.columns.append(self.allocator, ProgressColumn.custom(render_fn));
    }

    pub fn withCompleted(self: Progress, c: usize) Progress {
        var p = self;
        p.completed = c;
        return p;
    }

    pub fn withTotal(self: Progress, t: usize) Progress {
        var p = self;
        p.total = t;
        return p;
    }

    pub fn withDescription(self: Progress, desc: []const u8) Progress {
        var p = self;
        p.description = desc;
        return p;
    }

    pub fn withTiming(self: Progress) Progress {
        var p = self;
        p.start_time = p.source.now(.monotonic);
        return p;
    }

    pub fn asIndeterminate(self: Progress) Progress {
        var p = self;
        p.indeterminate = true;
        return p;
    }

    pub fn withSeparator(self: Progress, sep: []const u8) Progress {
        var p = self;
        p.separator = sep;
        return p;
    }

    pub fn percentage(self: Progress) f64 {
        if (self.total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.completed)) / @as(f64, @floatFromInt(self.total)) * 100.0;
    }

    pub fn isFinished(self: Progress) bool {
        return self.completed >= self.total;
    }

    pub fn advance(self: *Progress, amount: usize) void {
        self.completed = @min(self.completed + amount, self.total);
    }

    pub fn calculateElapsed(self: Progress) u64 {
        const start = self.start_time orelse return 0;
        const diff = self.source.now(.monotonic) -| start;
        if (diff <= 0) return 0;
        const seconds = @as(u64, @intCast(diff)) / std.time.ns_per_s;
        assert(seconds <= std.math.maxInt(i64));
        return seconds;
    }

    pub fn estimateRemaining(self: Progress) ?u64 {
        if (self.completed == 0 or self.start_time == null) return null;
        if (self.completed >= self.total) return 0;

        const elapsed = self.calculateElapsed();
        if (elapsed == 0) return null;

        const rate: f64 = @as(f64, @floatFromInt(self.completed)) / @as(f64, @floatFromInt(elapsed));
        if (rate == 0) return null;

        const remaining: f64 = @as(f64, @floatFromInt(self.total - self.completed)) / rate;
        return std.math.lossyCast(u64, remaining);
    }

    pub fn calculateSpeed(self: Progress) f64 {
        const elapsed = self.calculateElapsed();
        if (elapsed == 0) return 0;
        return @as(f64, @floatFromInt(self.completed)) / @as(f64, @floatFromInt(elapsed));
    }

    fn buildContext(self: Progress) ColumnRenderContext {
        return .{
            .completed = self.completed,
            .total = self.total,
            .percentage = self.percentage(),
            .elapsed_seconds = self.calculateElapsed(),
            .eta_seconds = self.estimateRemaining(),
            .speed = self.calculateSpeed(),
            .description = self.description,
            .is_finished = self.isFinished(),
            .is_indeterminate = self.indeterminate,
            .current_ms = @divFloor(self.source.now(.wall), std.time.ns_per_ms),
        };
    }

    fn calculateColumnWidths(self: Progress, max_width: usize, allocator: std.mem.Allocator) ![]usize {
        const visible_columns = blk: {
            var count: usize = 0;
            for (self.columns.items) |col| {
                if (col.visible) count += 1;
            }
            break :blk count;
        };

        if (visible_columns == 0) {
            return try allocator.alloc(usize, 0);
        }

        const widths = try allocator.alloc(usize, self.columns.items.len);
        @memset(widths, 0);

        var total_fixed: usize = 0;
        var total_ratio: usize = 0;
        var auto_count: usize = 0;
        const separator_space = if (visible_columns > 1) (visible_columns - 1) * self.separator.len else 0;

        for (self.columns.items, 0..) |col, i| {
            if (!col.visible) continue;

            switch (col.width) {
                .fixed => |w| {
                    widths[i] = w;
                    total_fixed += w;
                },
                .ratio => |r| total_ratio += r,
                .auto => auto_count += 1,
            }
        }

        var remaining = if (max_width > total_fixed + separator_space)
            max_width - total_fixed - separator_space
        else
            0;

        if (total_ratio > 0 and remaining > 0) {
            const ratio_space = remaining;
            for (self.columns.items, 0..) |col, i| {
                if (!col.visible) continue;
                if (col.width == .ratio) {
                    const r = col.width.ratio;
                    const w = (ratio_space * r) / total_ratio;
                    widths[i] = w;
                    remaining -= w;
                }
            }
        }

        if (auto_count > 0 and remaining > 0) {
            const auto_width = remaining / auto_count;
            for (self.columns.items, 0..) |col, i| {
                if (!col.visible) continue;
                if (col.width == .auto) {
                    widths[i] = auto_width;
                }
            }
        }

        for (self.columns.items, 0..) |col, i| {
            if (col.min_width) |min| {
                if (widths[i] < min) widths[i] = min;
            }
            if (col.max_width) |max| {
                if (widths[i] > max) widths[i] = max;
            }
        }

        return widths;
    }

    pub fn render(self: Progress, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        if (self.columns.items.len == 0) {
            return &.{};
        }

        const ctx = self.buildContext();
        const widths = try self.calculateColumnWidths(max_width, allocator);
        defer allocator.free(widths);

        var segments: std.ArrayList(Segment) = .empty;
        var first = true;

        for (self.columns.items, 0..) |col, i| {
            if (!col.visible) continue;

            if (!first) {
                try segments.append(allocator, Segment.plain(self.separator));
            }
            first = false;

            const col_segments = try col.render(ctx, widths[i], allocator);
            defer allocator.free(col_segments);

            for (col_segments) |seg| {
                try segments.append(allocator, seg);
            }
        }

        return segments.toOwnedSlice(allocator);
    }
};

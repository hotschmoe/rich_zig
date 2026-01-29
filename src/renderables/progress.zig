const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const Color = @import("../color.zig").Color;

pub const ProgressBar = struct {
    completed: usize = 0,
    total: usize = 100,
    width: usize = 40,
    complete_style: Style = Style.empty.foreground(Color.green),
    finished_style: Style = Style.empty.foreground(Color.bright_green),
    incomplete_style: Style = Style.empty.dim(),
    complete_char: []const u8 = "\u{2501}",
    incomplete_char: []const u8 = "\u{2501}",
    pulse: bool = false,

    pub fn init() ProgressBar {
        return .{};
    }

    pub fn withCompleted(self: ProgressBar, c: usize) ProgressBar {
        var p = self;
        p.completed = c;
        return p;
    }

    pub fn withTotal(self: ProgressBar, t: usize) ProgressBar {
        var p = self;
        p.total = t;
        return p;
    }

    pub fn withWidth(self: ProgressBar, w: usize) ProgressBar {
        var p = self;
        p.width = w;
        return p;
    }

    pub fn withCompleteStyle(self: ProgressBar, s: Style) ProgressBar {
        var p = self;
        p.complete_style = s;
        return p;
    }

    pub fn withIncompleteStyle(self: ProgressBar, s: Style) ProgressBar {
        var p = self;
        p.incomplete_style = s;
        return p;
    }

    pub fn render(self: ProgressBar, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        const bar_width = @min(self.width, max_width);
        const ratio: f64 = if (self.total > 0)
            @as(f64, @floatFromInt(self.completed)) / @as(f64, @floatFromInt(self.total))
        else
            0.0;
        const complete_width: usize = @intFromFloat(@min(ratio, 1.0) * @as(f64, @floatFromInt(bar_width)));
        const incomplete_width = bar_width - complete_width;

        const style = if (self.completed >= self.total) self.finished_style else self.complete_style;

        // Complete portion
        var i: usize = 0;
        while (i < complete_width) : (i += 1) {
            try segments.append(allocator, Segment.styled(self.complete_char, style));
        }

        // Incomplete portion
        i = 0;
        while (i < incomplete_width) : (i += 1) {
            try segments.append(allocator, Segment.styled(self.incomplete_char, self.incomplete_style));
        }

        return segments.toOwnedSlice(allocator);
    }

    pub fn percentage(self: ProgressBar) f64 {
        if (self.total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.completed)) / @as(f64, @floatFromInt(self.total)) * 100.0;
    }

    pub fn isFinished(self: ProgressBar) bool {
        return self.completed >= self.total;
    }

    pub fn advance(self: *ProgressBar, amount: usize) void {
        self.completed = @min(self.completed + amount, self.total);
    }
};

pub const Spinner = struct {
    frames: []const []const u8 = &DEFAULT_FRAMES,
    current_frame: usize = 0,
    style: Style = Style.empty,

    const DEFAULT_FRAMES = [_][]const u8{
        "\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}",
        "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}",
        "\u{2807}", "\u{280F}",
    };

    const DOTS_FRAMES = [_][]const u8{
        "\u{28F7}", "\u{28EF}", "\u{28DF}", "\u{287F}",
        "\u{28BF}", "\u{28FB}", "\u{28FD}", "\u{28FE}",
    };

    const LINE_FRAMES = [_][]const u8{ "-", "\\", "|", "/" };

    pub fn init() Spinner {
        return .{};
    }

    pub fn dots() Spinner {
        return .{ .frames = &DOTS_FRAMES };
    }

    pub fn line() Spinner {
        return .{ .frames = &LINE_FRAMES };
    }

    pub fn withStyle(self: Spinner, s: Style) Spinner {
        var sp = self;
        sp.style = s;
        return sp;
    }

    pub fn advance(self: *Spinner) void {
        self.current_frame = (self.current_frame + 1) % self.frames.len;
    }

    pub fn render(self: Spinner, allocator: std.mem.Allocator) ![]Segment {
        const result = try allocator.alloc(Segment, 1);
        result[0] = Segment.styled(self.frames[self.current_frame], self.style);
        return result;
    }

    pub fn renderWidth(self: Spinner, width: usize, allocator: std.mem.Allocator) ![]Segment {
        _ = width;
        return self.render(allocator);
    }
};

// Tests
test "ProgressBar.init" {
    const bar = ProgressBar.init();
    try std.testing.expectEqual(@as(usize, 0), bar.completed);
    try std.testing.expectEqual(@as(usize, 100), bar.total);
}

test "ProgressBar.percentage" {
    const bar = ProgressBar.init().withCompleted(50).withTotal(100);
    try std.testing.expectEqual(@as(f64, 50.0), bar.percentage());
}

test "ProgressBar.percentage zero total" {
    const bar = ProgressBar.init().withTotal(0);
    try std.testing.expectEqual(@as(f64, 0.0), bar.percentage());
}

test "ProgressBar.isFinished" {
    const incomplete = ProgressBar.init().withCompleted(50).withTotal(100);
    try std.testing.expect(!incomplete.isFinished());

    const complete = ProgressBar.init().withCompleted(100).withTotal(100);
    try std.testing.expect(complete.isFinished());
}

test "ProgressBar.advance" {
    var bar = ProgressBar.init().withCompleted(0).withTotal(100);
    bar.advance(10);
    try std.testing.expectEqual(@as(usize, 10), bar.completed);

    bar.advance(100);
    try std.testing.expectEqual(@as(usize, 100), bar.completed); // Clamped to total
}

test "ProgressBar.render" {
    const allocator = std.testing.allocator;
    const bar = ProgressBar.init().withCompleted(50).withTotal(100).withWidth(10);

    const segments = try bar.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 10), segments.len);
}

test "Spinner.init" {
    const spinner = Spinner.init();
    try std.testing.expectEqual(@as(usize, 0), spinner.current_frame);
}

test "Spinner.advance" {
    var spinner = Spinner.init();
    spinner.advance();
    try std.testing.expectEqual(@as(usize, 1), spinner.current_frame);
}

test "Spinner.render" {
    const allocator = std.testing.allocator;
    const spinner = Spinner.init();

    const segments = try spinner.render(allocator);
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
}

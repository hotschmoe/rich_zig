const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const cells = @import("../cells.zig");
const segment = @import("../segment.zig");

pub const Padding = struct {
    content: []const Segment,
    top: u8 = 0,
    right: u8 = 0,
    bottom: u8 = 0,
    left: u8 = 0,
    style: ?Style = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, content: []const Segment) Padding {
        return .{
            .content = content,
            .allocator = allocator,
        };
    }

    pub fn uniform(self: Padding, n: u8) Padding {
        var p = self;
        p.top = n;
        p.right = n;
        p.bottom = n;
        p.left = n;
        return p;
    }

    pub fn horizontal(self: Padding, n: u8) Padding {
        var p = self;
        p.left = n;
        p.right = n;
        return p;
    }

    pub fn vertical(self: Padding, n: u8) Padding {
        var p = self;
        p.top = n;
        p.bottom = n;
        return p;
    }

    pub fn withPadding(self: Padding, top: u8, right: u8, bottom: u8, left: u8) Padding {
        var p = self;
        p.top = top;
        p.right = right;
        p.bottom = bottom;
        p.left = left;
        return p;
    }

    pub fn withStyle(self: Padding, s: Style) Padding {
        var p = self;
        p.style = s;
        return p;
    }

    pub fn render(self: Padding, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var result: std.ArrayList(Segment) = .empty;

        // Split content into lines
        var lines: std.ArrayList([]const Segment) = .empty;
        defer lines.deinit(allocator);

        var line_start: usize = 0;
        for (self.content, 0..) |seg, i| {
            if (std.mem.eql(u8, seg.text, "\n")) {
                try lines.append(allocator, self.content[line_start..i]);
                line_start = i + 1;
            }
        }
        if (line_start < self.content.len) {
            try lines.append(allocator, self.content[line_start..]);
        }
        if (lines.items.len == 0) {
            try lines.append(allocator, &[_]Segment{});
        }

        // Calculate max content width
        var max_content_width: usize = 0;
        for (lines.items) |line| {
            const line_width = segment.totalCellLength(line);
            if (line_width > max_content_width) {
                max_content_width = line_width;
            }
        }

        const total_width = max_content_width + self.left + self.right;
        const effective_width = @min(total_width, max_width);

        // Top padding
        var i: u8 = 0;
        while (i < self.top) : (i += 1) {
            try self.renderBlankLine(&result, allocator, effective_width);
        }

        // Content lines with left/right padding
        for (lines.items) |line| {
            try self.renderContentLine(&result, allocator, line, max_content_width);
        }

        // Bottom padding
        i = 0;
        while (i < self.bottom) : (i += 1) {
            try self.renderBlankLine(&result, allocator, effective_width);
        }

        return result.toOwnedSlice(allocator);
    }

    fn renderBlankLine(self: Padding, result: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize) !void {
        for (0..width) |_| {
            try result.append(allocator, if (self.style) |s|
                Segment.styled(" ", s)
            else
                Segment.plain(" "));
        }
        try result.append(allocator, Segment.line());
    }

    fn renderContentLine(self: Padding, result: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const Segment, max_content_width: usize) !void {
        // Left padding
        for (0..self.left) |_| {
            try result.append(allocator, if (self.style) |s|
                Segment.styled(" ", s)
            else
                Segment.plain(" "));
        }

        // Content
        for (line) |seg| {
            try result.append(allocator, seg);
        }

        // Right padding to fill to max_content_width
        const line_width = segment.totalCellLength(line);
        const right_fill = if (max_content_width > line_width) max_content_width - line_width else 0;
        for (0..right_fill + self.right) |_| {
            try result.append(allocator, if (self.style) |s|
                Segment.styled(" ", s)
            else
                Segment.plain(" "));
        }

        try result.append(allocator, Segment.line());
    }
};

// Tests
test "Padding.init" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const padding = Padding.init(allocator, &segments);

    try std.testing.expectEqual(@as(u8, 0), padding.top);
    try std.testing.expectEqual(@as(u8, 0), padding.right);
}

test "Padding.uniform" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const padding = Padding.init(allocator, &segments).uniform(2);

    try std.testing.expectEqual(@as(u8, 2), padding.top);
    try std.testing.expectEqual(@as(u8, 2), padding.right);
    try std.testing.expectEqual(@as(u8, 2), padding.bottom);
    try std.testing.expectEqual(@as(u8, 2), padding.left);
}

test "Padding.horizontal" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const padding = Padding.init(allocator, &segments).horizontal(3);

    try std.testing.expectEqual(@as(u8, 0), padding.top);
    try std.testing.expectEqual(@as(u8, 3), padding.right);
    try std.testing.expectEqual(@as(u8, 0), padding.bottom);
    try std.testing.expectEqual(@as(u8, 3), padding.left);
}

test "Padding.vertical" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const padding = Padding.init(allocator, &segments).vertical(1);

    try std.testing.expectEqual(@as(u8, 1), padding.top);
    try std.testing.expectEqual(@as(u8, 0), padding.right);
    try std.testing.expectEqual(@as(u8, 1), padding.bottom);
    try std.testing.expectEqual(@as(u8, 0), padding.left);
}

test "Padding.render basic" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const padding = Padding.init(allocator, &segments).uniform(1);

    const rendered = try padding.render(80, allocator);
    defer allocator.free(rendered);

    // Should have: 1 blank line top + 1 content line + 1 blank line bottom = 3 lines
    var line_count: usize = 0;
    for (rendered) |seg| {
        if (std.mem.eql(u8, seg.text, "\n")) {
            line_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), line_count);
}

test "Padding.withPadding" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Test")};
    const padding = Padding.init(allocator, &segments).withPadding(1, 2, 3, 4);

    try std.testing.expectEqual(@as(u8, 1), padding.top);
    try std.testing.expectEqual(@as(u8, 2), padding.right);
    try std.testing.expectEqual(@as(u8, 3), padding.bottom);
    try std.testing.expectEqual(@as(u8, 4), padding.left);
}

test "Padding.withStyle" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Test")};
    const padding = Padding.init(allocator, &segments).withStyle(Style.empty.bold());

    try std.testing.expect(padding.style != null);
    try std.testing.expect(padding.style.?.hasAttribute(.bold));
}

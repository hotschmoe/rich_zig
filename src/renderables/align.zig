const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const cells = @import("../cells.zig");
const segment = @import("../segment.zig");

pub const HAlign = enum {
    left,
    center,
    right,
};

pub const VAlign = enum {
    top,
    middle,
    bottom,
};

pub const Align = struct {
    content: []const Segment,
    horizontal: HAlign = .left,
    vertical: VAlign = .top,
    width: ?usize = null,
    height: ?usize = null,
    pad_style: ?Style = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, content: []const Segment) Align {
        return .{
            .content = content,
            .allocator = allocator,
        };
    }

    pub fn left(self: Align) Align {
        var a = self;
        a.horizontal = .left;
        return a;
    }

    pub fn center(self: Align) Align {
        var a = self;
        a.horizontal = .center;
        return a;
    }

    pub fn right(self: Align) Align {
        var a = self;
        a.horizontal = .right;
        return a;
    }

    pub fn top(self: Align) Align {
        var a = self;
        a.vertical = .top;
        return a;
    }

    pub fn middle(self: Align) Align {
        var a = self;
        a.vertical = .middle;
        return a;
    }

    pub fn bottom(self: Align) Align {
        var a = self;
        a.vertical = .bottom;
        return a;
    }

    pub fn withWidth(self: Align, w: usize) Align {
        var a = self;
        a.width = w;
        return a;
    }

    pub fn withHeight(self: Align, h: usize) Align {
        var a = self;
        a.height = h;
        return a;
    }

    pub fn withPadStyle(self: Align, s: Style) Align {
        var a = self;
        a.pad_style = s;
        return a;
    }

    pub fn render(self: Align, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
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

        // Calculate dimensions
        var max_content_width: usize = 0;
        for (lines.items) |line| {
            const line_width = segment.totalCellLength(line);
            if (line_width > max_content_width) {
                max_content_width = line_width;
            }
        }

        const target_width = self.width orelse @min(max_content_width, max_width);
        const content_height = lines.items.len;
        const target_height = self.height orelse content_height;

        // Calculate vertical padding
        const top_padding: usize = switch (self.vertical) {
            .top => 0,
            .middle => if (target_height > content_height) (target_height - content_height) / 2 else 0,
            .bottom => if (target_height > content_height) target_height - content_height else 0,
        };
        const bottom_padding: usize = if (target_height > content_height + top_padding)
            target_height - content_height - top_padding
        else
            0;

        // Top padding lines
        for (0..top_padding) |_| {
            try self.renderBlankLine(&result, allocator, target_width);
        }

        // Content lines with horizontal alignment
        for (lines.items) |line| {
            try self.renderAlignedLine(&result, allocator, line, target_width);
        }

        // Bottom padding lines
        for (0..bottom_padding) |_| {
            try self.renderBlankLine(&result, allocator, target_width);
        }

        return result.toOwnedSlice(allocator);
    }

    fn renderBlankLine(self: Align, result: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize) !void {
        for (0..width) |_| {
            try result.append(allocator, if (self.pad_style) |s|
                Segment.styled(" ", s)
            else
                Segment.plain(" "));
        }
        try result.append(allocator, Segment.line());
    }

    fn renderAlignedLine(self: Align, result: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const Segment, target_width: usize) !void {
        const line_width = segment.totalCellLength(line);
        const padding_total = if (target_width > line_width) target_width - line_width else 0;

        const left_padding: usize = switch (self.horizontal) {
            .left => 0,
            .center => padding_total / 2,
            .right => padding_total,
        };
        const right_padding = padding_total - left_padding;

        // Left padding
        for (0..left_padding) |_| {
            try result.append(allocator, if (self.pad_style) |s|
                Segment.styled(" ", s)
            else
                Segment.plain(" "));
        }

        // Content
        for (line) |seg| {
            try result.append(allocator, seg);
        }

        // Right padding
        for (0..right_padding) |_| {
            try result.append(allocator, if (self.pad_style) |s|
                Segment.styled(" ", s)
            else
                Segment.plain(" "));
        }

        try result.append(allocator, Segment.line());
    }
};

// Tests
test "Align.init" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const align_obj = Align.init(allocator, &segments);

    try std.testing.expectEqual(HAlign.left, align_obj.horizontal);
    try std.testing.expectEqual(VAlign.top, align_obj.vertical);
}

test "Align.center" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const align_obj = Align.init(allocator, &segments).center();

    try std.testing.expectEqual(HAlign.center, align_obj.horizontal);
}

test "Align.right" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const align_obj = Align.init(allocator, &segments).right();

    try std.testing.expectEqual(HAlign.right, align_obj.horizontal);
}

test "Align.middle" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const align_obj = Align.init(allocator, &segments).middle();

    try std.testing.expectEqual(VAlign.middle, align_obj.vertical);
}

test "Align.bottom" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hello")};
    const align_obj = Align.init(allocator, &segments).bottom();

    try std.testing.expectEqual(VAlign.bottom, align_obj.vertical);
}

test "Align.withWidth" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const align_obj = Align.init(allocator, &segments).withWidth(10);

    try std.testing.expectEqual(@as(?usize, 10), align_obj.width);
}

test "Align.withHeight" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const align_obj = Align.init(allocator, &segments).withHeight(5);

    try std.testing.expectEqual(@as(?usize, 5), align_obj.height);
}

test "Align.render left alignment" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const align_obj = Align.init(allocator, &segments).left().withWidth(5);

    const rendered = try align_obj.render(80, allocator);
    defer allocator.free(rendered);

    // Content + padding + newline
    try std.testing.expect(rendered.len > 0);

    // First segment should be "Hi"
    try std.testing.expectEqualStrings("Hi", rendered[0].text);
}

test "Align.render center alignment" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const align_obj = Align.init(allocator, &segments).center().withWidth(6);

    const rendered = try align_obj.render(80, allocator);
    defer allocator.free(rendered);

    // Should have 2 spaces left padding, "Hi", 2 spaces right padding, newline
    // 2 + 2 + 2 + 1 = 7 segments
    try std.testing.expect(rendered.len >= 5);
}

test "Align.render right alignment" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const align_obj = Align.init(allocator, &segments).right().withWidth(5);

    const rendered = try align_obj.render(80, allocator);
    defer allocator.free(rendered);

    // Should have 3 spaces padding before "Hi"
    try std.testing.expect(rendered.len >= 4);
    // First 3 should be spaces
    try std.testing.expectEqualStrings(" ", rendered[0].text);
    try std.testing.expectEqualStrings(" ", rendered[1].text);
    try std.testing.expectEqualStrings(" ", rendered[2].text);
    try std.testing.expectEqualStrings("Hi", rendered[3].text);
}

test "Align.render with vertical middle" {
    const allocator = std.testing.allocator;
    const segments = [_]Segment{Segment.plain("Hi")};
    const align_obj = Align.init(allocator, &segments).middle().withHeight(3).withWidth(2);

    const rendered = try align_obj.render(80, allocator);
    defer allocator.free(rendered);

    // Should have 3 lines
    var line_count: usize = 0;
    for (rendered) |seg| {
        if (std.mem.eql(u8, seg.text, "\n")) {
            line_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), line_count);
}

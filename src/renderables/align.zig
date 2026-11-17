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

    pub fn init(content: []const Segment) Align {
        return .{ .content = content };
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

        const lines = try segment.splitIntoLines(self.content, allocator);
        defer allocator.free(lines);

        const max_content_width = segment.maxLineWidth(lines);
        const target_width = self.width orelse @min(max_content_width, max_width);
        const content_height = lines.len;
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

        for (0..top_padding) |_| {
            try self.renderBlankLine(&result, allocator, target_width);
        }

        for (lines) |line| {
            try self.renderAlignedLine(&result, allocator, line, target_width);
        }

        for (0..bottom_padding) |_| {
            try self.renderBlankLine(&result, allocator, target_width);
        }

        return result.toOwnedSlice(allocator);
    }

    fn renderBlankLine(self: Align, result: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize) !void {
        try self.renderSpaces(result, allocator, width);
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

        try self.renderSpaces(result, allocator, left_padding);

        for (line) |seg| {
            try result.append(allocator, seg);
        }

        try self.renderSpaces(result, allocator, right_padding);
        try result.append(allocator, Segment.line());
    }

    fn renderSpaces(self: Align, result: *std.ArrayList(Segment), allocator: std.mem.Allocator, count: usize) !void {
        const space_seg = Segment.styledOptional(" ", self.pad_style);
        for (0..count) |_| {
            try result.append(allocator, space_seg);
        }
    }
};

// Tests

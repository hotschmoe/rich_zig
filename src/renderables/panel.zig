const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const Text = @import("../text.zig").Text;
const BoxStyle = @import("../box.zig").BoxStyle;
const cells = @import("../cells.zig");

pub const Panel = struct {
    content: Content,
    title: ?[]const u8 = null,
    subtitle: ?[]const u8 = null,
    box_style: BoxStyle = BoxStyle.rounded,
    style: Style = Style.empty,
    border_style: Style = Style.empty,
    title_style: Style = Style.empty,
    subtitle_style: Style = Style.empty,
    width: ?usize = null,
    padding: Padding = .{ .top = 0, .right = 1, .bottom = 0, .left = 1 },
    expand: bool = true,
    allocator: std.mem.Allocator,

    pub const Padding = struct {
        top: u8 = 0,
        right: u8 = 1,
        bottom: u8 = 0,
        left: u8 = 1,
    };

    pub const Content = union(enum) {
        text: []const u8,
        styled_text: Text,
        segments: []const Segment,
    };

    pub fn fromText(allocator: std.mem.Allocator, text: []const u8) Panel {
        return .{
            .content = .{ .text = text },
            .allocator = allocator,
        };
    }

    pub fn fromStyledText(allocator: std.mem.Allocator, txt: Text) Panel {
        return .{
            .content = .{ .styled_text = txt },
            .allocator = allocator,
        };
    }

    pub fn withTitle(self: Panel, title: []const u8) Panel {
        var p = self;
        p.title = title;
        return p;
    }

    pub fn withSubtitle(self: Panel, subtitle: []const u8) Panel {
        var p = self;
        p.subtitle = subtitle;
        return p;
    }

    pub fn withWidth(self: Panel, w: usize) Panel {
        var p = self;
        p.width = w;
        return p;
    }

    pub fn withPadding(self: Panel, top: u8, right: u8, bottom: u8, left: u8) Panel {
        var p = self;
        p.padding = .{ .top = top, .right = right, .bottom = bottom, .left = left };
        return p;
    }

    pub fn withBorderStyle(self: Panel, style: Style) Panel {
        var p = self;
        p.border_style = style;
        return p;
    }

    pub fn withTitleStyle(self: Panel, style: Style) Panel {
        var p = self;
        p.title_style = style;
        return p;
    }

    pub fn rounded(self: Panel) Panel {
        var p = self;
        p.box_style = BoxStyle.rounded;
        return p;
    }

    pub fn square(self: Panel) Panel {
        var p = self;
        p.box_style = BoxStyle.square;
        return p;
    }

    pub fn heavy(self: Panel) Panel {
        var p = self;
        p.box_style = BoxStyle.heavy;
        return p;
    }

    pub fn double(self: Panel) Panel {
        var p = self;
        p.box_style = BoxStyle.double;
        return p;
    }

    pub fn ascii(self: Panel) Panel {
        var p = self;
        p.box_style = BoxStyle.ascii;
        return p;
    }

    pub fn render(self: Panel, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;
        const b = self.box_style;

        const panel_width = self.width orelse max_width;
        const inner_width = if (panel_width > 2) panel_width - 2 else 0;
        const content_width = if (inner_width > self.padding.left + self.padding.right)
            inner_width - self.padding.left - self.padding.right
        else
            0;

        // Get content lines
        const content_text = switch (self.content) {
            .text => |t| t,
            .styled_text => |t| t.plain,
            .segments => "",
        };

        // Split content into lines
        var content_lines: std.ArrayList([]const u8) = .empty;
        defer content_lines.deinit(allocator);

        var line_start: usize = 0;
        for (content_text, 0..) |c, i| {
            if (c == '\n') {
                try content_lines.append(allocator, content_text[line_start..i]);
                line_start = i + 1;
            }
        }
        if (line_start < content_text.len) {
            try content_lines.append(allocator, content_text[line_start..]);
        }
        if (content_lines.items.len == 0) {
            try content_lines.append(allocator, "");
        }

        // Top border with optional title
        try self.renderTopBorder(&segments, allocator, inner_width, b);

        // Padding top
        var i: u8 = 0;
        while (i < self.padding.top) : (i += 1) {
            try self.renderEmptyLine(&segments, allocator, inner_width, b);
        }

        // Content lines
        for (content_lines.items) |line| {
            try self.renderContentLine(&segments, allocator, line, inner_width, content_width, b);
        }

        // Padding bottom
        i = 0;
        while (i < self.padding.bottom) : (i += 1) {
            try self.renderEmptyLine(&segments, allocator, inner_width, b);
        }

        // Bottom border with optional subtitle
        try self.renderBottomBorder(&segments, allocator, inner_width, b);

        return segments.toOwnedSlice(allocator);
    }

    fn renderTopBorder(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.top_left, self.border_style));

        if (self.title) |title| {
            const title_len = cells.cellLen(title);
            const available = if (width > title_len + 2) width - title_len - 2 else 0;
            const left_pad = available / 2;
            const right_pad = available - left_pad;

            try self.renderHorizontal(segments, allocator, left_pad, b);
            try segments.append(allocator, Segment.plain(" "));
            try segments.append(allocator, Segment.styled(title, self.title_style));
            try segments.append(allocator, Segment.plain(" "));
            try self.renderHorizontal(segments, allocator, right_pad, b);
        } else {
            try self.renderHorizontal(segments, allocator, width, b);
        }

        try segments.append(allocator, Segment.styled(b.top_right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderBottomBorder(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.bottom_left, self.border_style));

        if (self.subtitle) |subtitle| {
            const subtitle_len = cells.cellLen(subtitle);
            const available = if (width > subtitle_len + 2) width - subtitle_len - 2 else 0;
            const left_pad = available / 2;
            const right_pad = available - left_pad;

            try self.renderHorizontal(segments, allocator, left_pad, b);
            try segments.append(allocator, Segment.plain(" "));
            try segments.append(allocator, Segment.styled(subtitle, self.subtitle_style));
            try segments.append(allocator, Segment.plain(" "));
            try self.renderHorizontal(segments, allocator, right_pad, b);
        } else {
            try self.renderHorizontal(segments, allocator, width, b);
        }

        try segments.append(allocator, Segment.styled(b.bottom_right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderHorizontal(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, count: usize, b: BoxStyle) !void {
        for (0..count) |_| {
            try segments.append(allocator, Segment.styled(b.horizontal, self.border_style));
        }
    }

    fn renderEmptyLine(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));
        try self.renderSpaces(segments, allocator, width);
        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderContentLine(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8, _: usize, content_width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));
        try self.renderSpaces(segments, allocator, self.padding.left);

        const line_len = cells.cellLen(line);
        try segments.append(allocator, Segment.styledOptional(line, if (self.style.isEmpty()) null else self.style));

        // Pad to content width
        if (line_len < content_width) {
            try self.renderSpaces(segments, allocator, content_width - line_len);
        }

        try self.renderSpaces(segments, allocator, self.padding.right);
        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderSpaces(_: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, count: usize) !void {
        for (0..count) |_| {
            try segments.append(allocator, Segment.plain(" "));
        }
    }
};

// Tests
test "Panel.fromText" {
    const allocator = std.testing.allocator;
    const panel = Panel.fromText(allocator, "Hello");

    try std.testing.expectEqualStrings("Hello", panel.content.text);
}

test "Panel.withTitle" {
    const allocator = std.testing.allocator;
    const panel = Panel.fromText(allocator, "Content").withTitle("Title");

    try std.testing.expectEqualStrings("Title", panel.title.?);
}

test "Panel.render basic" {
    const allocator = std.testing.allocator;
    const panel = Panel.fromText(allocator, "Hello").withWidth(20);

    const segments = try panel.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len > 0);
}

test "Panel.render with title" {
    const allocator = std.testing.allocator;
    const panel = Panel.fromText(allocator, "Content").withTitle("Title").withWidth(30);

    const segments = try panel.render(80, allocator);
    defer allocator.free(segments);

    // Should find title somewhere in segments
    var found_title = false;
    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "Title") != null) {
            found_title = true;
            break;
        }
    }
    try std.testing.expect(found_title);
}

test "Panel box styles" {
    const allocator = std.testing.allocator;

    const rounded = Panel.fromText(allocator, "Test").rounded();
    try std.testing.expectEqualStrings("\u{256D}", rounded.box_style.top_left);

    const heavy_panel = Panel.fromText(allocator, "Test").heavy();
    try std.testing.expectEqualStrings("\u{250F}", heavy_panel.box_style.top_left);
}

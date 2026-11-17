const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const segment_mod = @import("../segment.zig");
const Style = @import("../style.zig").Style;
const Color = @import("../color.zig").Color;
const Text = @import("../text.zig").Text;
const BoxStyle = @import("../box.zig").BoxStyle;
const cells = @import("../cells.zig");

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const VOverflow = enum {
    clip,
    visible,
    ellipsis,
};

pub const Panel = struct {
    content: Content,
    title: ?[]const u8 = null,
    subtitle: ?[]const u8 = null,
    box_style: BoxStyle = BoxStyle.rounded,
    style: Style = Style.empty,
    border_style: Style = Style.empty,
    title_style: Style = Style.empty,
    subtitle_style: Style = Style.empty,
    title_align: Alignment = .center,
    subtitle_align: Alignment = .center,
    width: ?usize = null,
    height: ?usize = null,
    vertical_overflow: VOverflow = .clip,
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

    pub fn fromSegments(allocator: std.mem.Allocator, segs: []const Segment) Panel {
        return .{
            .content = .{ .segments = segs },
            .allocator = allocator,
        };
    }

    /// Convenience alias for fromSegments - creates a Panel from pre-rendered content.
    /// Use this when you have segments from another renderable (e.g., Table.render(), Json.render()).
    pub fn fromRendered(allocator: std.mem.Allocator, segs: []const Segment) Panel {
        return fromSegments(allocator, segs);
    }

    /// Creates an info panel with blue border and rounded style.
    pub fn info(allocator: std.mem.Allocator, text: []const u8) Panel {
        return fromText(allocator, text)
            .withBorderStyle(Style.empty.fg(Color.blue))
            .rounded();
    }

    /// Creates a warning panel with yellow border, "Warning" title, and rounded style.
    pub fn warning(allocator: std.mem.Allocator, text: []const u8) Panel {
        return fromText(allocator, text)
            .withTitle("Warning")
            .withBorderStyle(Style.empty.fg(Color.yellow))
            .rounded();
    }

    /// Creates an error panel with red border, "Error" title, and rounded style.
    pub fn err(allocator: std.mem.Allocator, text: []const u8) Panel {
        return fromText(allocator, text)
            .withTitle("Error")
            .withBorderStyle(Style.empty.fg(Color.red))
            .rounded();
    }

    /// Creates a success panel with green border, "Success" title, and rounded style.
    pub fn success(allocator: std.mem.Allocator, text: []const u8) Panel {
        return fromText(allocator, text)
            .withTitle("Success")
            .withBorderStyle(Style.empty.fg(Color.green))
            .rounded();
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

    pub fn withHeight(self: Panel, h: usize) Panel {
        var p = self;
        p.height = h;
        return p;
    }

    pub fn withVerticalOverflow(self: Panel, v: VOverflow) Panel {
        var p = self;
        p.vertical_overflow = v;
        return p;
    }

    pub fn withPadding(self: Panel, top: u8, right: u8, bottom: u8, left: u8) Panel {
        var p = self;
        p.padding = .{ .top = top, .right = right, .bottom = bottom, .left = left };
        return p;
    }

    pub fn withBorderStyle(self: Panel, s: Style) Panel {
        var p = self;
        p.border_style = s;
        return p;
    }

    pub fn withTitleStyle(self: Panel, s: Style) Panel {
        var p = self;
        p.title_style = s;
        return p;
    }

    pub fn withTitleAlignment(self: Panel, alignment: Alignment) Panel {
        var p = self;
        p.title_align = alignment;
        return p;
    }

    pub fn withSubtitleAlignment(self: Panel, alignment: Alignment) Panel {
        var p = self;
        p.subtitle_align = alignment;
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

    pub fn measure(self: Panel, max_width: usize, _: std.mem.Allocator) !@import("../measure.zig").Measurement {
        const Meas = @import("../measure.zig").Measurement;
        const border_width: usize = 4; // left border + space + space + right border

        if (self.width) |w| {
            const clamped = @min(@as(usize, w), max_width);
            return Meas.init(clamped, clamped);
        }

        const content_measurement = Meas.fromText(switch (self.content) {
            .text => |t| t,
            .styled_text => |st| st.text,
            .segments => return Meas.init(border_width + 1, max_width),
        });

        return Meas.init(
            content_measurement.minimum + border_width,
            @min(content_measurement.maximum + border_width, max_width),
        );
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

        const content_lines = try self.getContentLines(allocator, content_width);
        defer {
            for (content_lines) |line| {
                if (self.content != .segments) {
                    allocator.free(line);
                }
            }
            allocator.free(content_lines);
        }

        const available_content_height: ?usize = if (self.height) |h| blk: {
            const borders: usize = 2;
            const vert_padding: usize = self.padding.top + self.padding.bottom;
            break :blk if (h > borders + vert_padding) h - borders - vert_padding else 0;
        } else null;

        try self.renderTopBorder(&segments, allocator, inner_width, b);

        var i: u8 = 0;
        while (i < self.padding.top) : (i += 1) {
            try self.renderEmptyLine(&segments, allocator, inner_width, b);
        }

        var lines_rendered: usize = 0;
        for (content_lines) |line| {
            if (available_content_height) |max_lines| {
                if (lines_rendered >= max_lines) {
                    if (self.vertical_overflow == .ellipsis and lines_rendered == max_lines) {
                        try self.renderEllipsisLine(&segments, allocator, inner_width, content_width, b);
                    }
                    break;
                }
            }
            try self.renderContentLineSegments(&segments, allocator, line, inner_width, content_width, b);
            lines_rendered += 1;
        }

        if (available_content_height) |max_lines| {
            while (lines_rendered < max_lines) : (lines_rendered += 1) {
                try self.renderEmptyLine(&segments, allocator, inner_width, b);
            }
        }

        i = 0;
        while (i < self.padding.bottom) : (i += 1) {
            try self.renderEmptyLine(&segments, allocator, inner_width, b);
        }

        try self.renderBottomBorder(&segments, allocator, inner_width, b);

        return segments.toOwnedSlice(allocator);
    }

    fn getContentLines(self: Panel, allocator: std.mem.Allocator, _: usize) ![][]const Segment {
        switch (self.content) {
            .text => |t| return self.splitTextIntoSegmentLines(allocator, t),
            .styled_text => |txt| return self.splitStyledTextIntoSegmentLines(allocator, txt),
            .segments => |segs| return segment_mod.splitIntoLines(segs, allocator),
        }
    }

    fn splitStyledTextIntoSegmentLines(_: Panel, allocator: std.mem.Allocator, txt: Text) ![][]const Segment {
        var lines: std.ArrayList([]const Segment) = .empty;
        errdefer {
            for (lines.items) |line| allocator.free(line);
            lines.deinit(allocator);
        }

        var line_start: usize = 0;

        for (txt.plain, 0..) |c, idx| {
            if (c == '\n') {
                var line_text = txt.slice(line_start, idx);
                defer line_text.deinit();
                const segs = try line_text.render(allocator);
                errdefer allocator.free(segs);
                try lines.append(allocator, segs);
                line_start = idx + 1;
            }
        }

        if (line_start < txt.plain.len) {
            var line_text = txt.slice(line_start, txt.plain.len);
            defer line_text.deinit();
            const segs = try line_text.render(allocator);
            errdefer allocator.free(segs);
            try lines.append(allocator, segs);
        }

        if (lines.items.len == 0) {
            const empty = try allocator.alloc(Segment, 1);
            errdefer allocator.free(empty);
            empty[0] = Segment.styledOptional("", if (txt.style.isEmpty()) null else txt.style);
            try lines.append(allocator, empty);
        }

        return lines.toOwnedSlice(allocator);
    }

    fn splitTextIntoSegmentLines(self: Panel, allocator: std.mem.Allocator, text: []const u8) ![][]const Segment {
        var lines: std.ArrayList([]const Segment) = .empty;
        errdefer {
            for (lines.items) |line| allocator.free(line);
            lines.deinit(allocator);
        }

        const style_to_use: ?Style = if (self.style.isEmpty()) null else self.style;
        var line_start: usize = 0;

        for (text, 0..) |c, idx| {
            if (c == '\n') {
                const segs = try self.makeSegmentLine(allocator, text[line_start..idx], style_to_use);
                errdefer allocator.free(segs);
                try lines.append(allocator, segs);
                line_start = idx + 1;
            }
        }

        if (line_start < text.len) {
            const segs = try self.makeSegmentLine(allocator, text[line_start..], style_to_use);
            errdefer allocator.free(segs);
            try lines.append(allocator, segs);
        }

        if (lines.items.len == 0) {
            const segs = try self.makeSegmentLine(allocator, "", null);
            errdefer allocator.free(segs);
            try lines.append(allocator, segs);
        }

        return lines.toOwnedSlice(allocator);
    }

    fn makeSegmentLine(_: Panel, allocator: std.mem.Allocator, text: []const u8, style: ?Style) ![]const Segment {
        const seg_arr = try allocator.alloc(Segment, 1);
        seg_arr[0] = Segment.styledOptional(text, style);
        return seg_arr;
    }

    fn renderTopBorder(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.top_left, self.border_style));

        if (self.title) |title| {
            const title_len = cells.cellLen(title);
            const available = if (width > title_len + 2) width - title_len - 2 else 0;

            const left_pad: usize = switch (self.title_align) {
                .left => 1,
                .center => available / 2,
                .right => if (available > 1) available - 1 else 0,
            };
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

            const left_pad: usize = switch (self.subtitle_align) {
                .left => 1,
                .center => available / 2,
                .right => if (available > 1) available - 1 else 0,
            };
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

    fn renderContentLineSegments(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const Segment, _: usize, content_width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));
        try self.renderSpaces(segments, allocator, self.padding.left);

        const line_len = segment_mod.totalCellLength(line);

        for (line) |seg| {
            try segments.append(allocator, seg);
        }

        if (line_len < content_width) {
            try self.renderSpaces(segments, allocator, content_width - line_len);
        }

        try self.renderSpaces(segments, allocator, self.padding.right);
        try segments.append(allocator, Segment.styled(b.right, self.border_style));
        try segments.append(allocator, Segment.line());
    }

    fn renderEllipsisLine(self: Panel, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, _: usize, content_width: usize, b: BoxStyle) !void {
        try segments.append(allocator, Segment.styled(b.left, self.border_style));
        try self.renderSpaces(segments, allocator, self.padding.left);

        const ellipsis = "...";
        const ellipsis_len = 3;

        try segments.append(allocator, Segment.styledOptional(ellipsis, if (self.style.isEmpty()) null else self.style));

        if (ellipsis_len < content_width) {
            try self.renderSpaces(segments, allocator, content_width - ellipsis_len);
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

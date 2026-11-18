const std = @import("std");
const Style = @import("style.zig").Style;
const cells = @import("cells.zig");

pub const ControlType = enum {
    bell,
    carriage_return,
    home,
    clear,
    show_cursor,
    hide_cursor,
    enable_alt_screen,
    disable_alt_screen,
    cursor_up,
    cursor_down,
    cursor_forward,
    cursor_backward,
    cursor_move_to_column,
    cursor_move_to,
    erase_in_line,
    set_window_title,
};

pub const ControlCode = union(ControlType) {
    bell: void,
    carriage_return: void,
    home: void,
    clear: void,
    show_cursor: void,
    hide_cursor: void,
    enable_alt_screen: void,
    disable_alt_screen: void,
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_backward: u16,
    cursor_move_to_column: u16,
    cursor_move_to: struct { x: u16, y: u16 },
    erase_in_line: u8,
    set_window_title: []const u8,

    pub fn toEscapeSequence(self: ControlCode, writer: anytype) !void {
        switch (self) {
            .bell => try writer.writeByte(0x07),
            .carriage_return => try writer.writeByte('\r'),
            .home => try writer.writeAll("\x1b[H"),
            .clear => try writer.writeAll("\x1b[2J"),
            .show_cursor => try writer.writeAll("\x1b[?25h"),
            .hide_cursor => try writer.writeAll("\x1b[?25l"),
            .enable_alt_screen => try writer.writeAll("\x1b[?1049h"),
            .disable_alt_screen => try writer.writeAll("\x1b[?1049l"),
            .cursor_up => |n| try writer.print("\x1b[{d}A", .{n}),
            .cursor_down => |n| try writer.print("\x1b[{d}B", .{n}),
            .cursor_forward => |n| try writer.print("\x1b[{d}C", .{n}),
            .cursor_backward => |n| try writer.print("\x1b[{d}D", .{n}),
            .cursor_move_to_column => |col| try writer.print("\x1b[{d}G", .{col}),
            .cursor_move_to => |pos| try writer.print("\x1b[{d};{d}H", .{ pos.y, pos.x }),
            .erase_in_line => |mode| try writer.print("\x1b[{d}K", .{mode}),
            .set_window_title => |title| try writer.print("\x1b]0;{s}\x07", .{title}),
        }
    }
};

pub const Segment = struct {
    text: []const u8,
    style: ?Style = null,
    control: ?ControlCode = null,

    pub fn plain(text: []const u8) Segment {
        return .{ .text = text };
    }

    pub fn styled(text: []const u8, style: Style) Segment {
        return .{ .text = text, .style = style };
    }

    pub fn styledOptional(text: []const u8, style: ?Style) Segment {
        return .{ .text = text, .style = style };
    }

    pub fn controlSegment(code: ControlCode) Segment {
        return .{ .text = "", .control = code };
    }

    pub fn line() Segment {
        return plain("\n");
    }

    pub fn space() Segment {
        return plain(" ");
    }

    pub fn cellLength(self: Segment) usize {
        if (self.control != null) return 0;
        return cells.cellLen(self.text);
    }

    pub fn isControl(self: Segment) bool {
        return self.control != null;
    }

    pub fn isEmpty(self: Segment) bool {
        return self.text.len == 0 and self.control == null;
    }

    pub fn isWhitespace(self: Segment) bool {
        if (self.control != null) return false;
        if (self.text.len == 0) return false;
        return std.mem.indexOfNone(u8, self.text, " \t\n\r") == null;
    }

    pub fn splitCells(self: Segment, pos: usize) struct { Segment, Segment } {
        if (self.control != null) {
            return .{ self, Segment{ .text = "" } };
        }

        const byte_pos = cells.cellToByteIndex(self.text, pos);

        return .{
            Segment{ .text = self.text[0..byte_pos], .style = self.style },
            Segment{ .text = self.text[byte_pos..], .style = self.style },
        };
    }

    pub fn withStyle(self: Segment, new_style: Style) Segment {
        return .{
            .text = self.text,
            .style = new_style,
            .control = self.control,
        };
    }

    pub fn withoutStyle(self: Segment) Segment {
        return .{
            .text = self.text,
            .style = null,
            .control = self.control,
        };
    }

    pub fn render(self: Segment, writer: anytype, color_system: @import("color.zig").ColorSystem) !void {
        if (self.control) |ctrl| {
            try ctrl.toEscapeSequence(writer);
            return;
        }

        if (self.style) |style| {
            if (!style.isEmpty()) {
                try style.renderAnsi(color_system, writer);
            }
        }

        try writer.writeAll(self.text);

        if (self.style) |style| {
            if (!style.isEmpty()) {
                try Style.renderReset(writer);
            }
            if (style.link != null) {
                try Style.renderHyperlinkEnd(writer);
            }
        }
    }
};

pub fn stripStyles(segments: []const Segment, allocator: std.mem.Allocator) ![]Segment {
    const result = try allocator.alloc(Segment, segments.len);
    for (segments, 0..) |seg, i| {
        result[i] = seg.withoutStyle();
    }
    return result;
}

pub fn joinText(segments: []const Segment, allocator: std.mem.Allocator) ![]u8 {
    var total_len: usize = 0;
    for (segments) |seg| {
        if (seg.control == null) {
            total_len += seg.text.len;
        }
    }

    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (segments) |seg| {
        if (seg.control == null) {
            @memcpy(result[pos..][0..seg.text.len], seg.text);
            pos += seg.text.len;
        }
    }

    return result;
}

pub fn totalCellLength(segments: []const Segment) usize {
    var total: usize = 0;
    for (segments) |seg| {
        total += seg.cellLength();
    }
    return total;
}

pub fn divide(segments: []const Segment, cuts: []const usize, allocator: std.mem.Allocator) ![][]Segment {
    if (cuts.len == 0) {
        const result = try allocator.alloc([]Segment, 1);
        result[0] = try allocator.dupe(Segment, segments);
        return result;
    }

    var result: std.ArrayList([]Segment) = .empty;
    var current_section: std.ArrayList(Segment) = .empty;

    var seg_idx: usize = 0;
    var seg_pos: usize = 0; // Current position within current segment
    var cell_pos: usize = 0;
    var cut_idx: usize = 0;

    while (seg_idx < segments.len) {
        const seg = segments[seg_idx];

        if (seg.control != null) {
            try current_section.append(allocator, seg);
            seg_idx += 1;
            continue;
        }

        const seg_cell_len = seg.cellLength();
        const seg_start_cell = cell_pos - seg_pos;
        const seg_end_cell = seg_start_cell + seg_cell_len;

        while (cut_idx < cuts.len and cuts[cut_idx] <= seg_end_cell) {
            const cut_cell = cuts[cut_idx];
            const cut_within_seg = cut_cell - seg_start_cell;

            if (cut_within_seg > seg_pos) {
                const split = seg.splitCells(cut_within_seg);
                const portion = split[0].splitCells(seg_pos);
                if (portion[1].text.len > 0) {
                    try current_section.append(allocator, portion[1]);
                }
            }

            try result.append(allocator, try current_section.toOwnedSlice(allocator));
            current_section = .empty;

            seg_pos = cut_within_seg;
            cut_idx += 1;
        }

        if (seg_pos < seg_cell_len) {
            const remaining = seg.splitCells(seg_pos)[1];
            if (remaining.text.len > 0) {
                try current_section.append(allocator, remaining);
            }
        }

        cell_pos = seg_end_cell;
        seg_pos = 0;
        seg_idx += 1;
    }

    try result.append(allocator, try current_section.toOwnedSlice(allocator));

    return result.toOwnedSlice(allocator);
}

pub fn splitIntoLines(segments: []const Segment, allocator: std.mem.Allocator) ![][]const Segment {
    var lines: std.ArrayList([]const Segment) = .empty;
    var line_start: usize = 0;

    for (segments, 0..) |seg, i| {
        if (std.mem.eql(u8, seg.text, "\n")) {
            try lines.append(allocator, segments[line_start..i]);
            line_start = i + 1;
        }
    }
    if (line_start < segments.len) {
        try lines.append(allocator, segments[line_start..]);
    }
    if (lines.items.len == 0) {
        try lines.append(allocator, &[_]Segment{});
    }

    return lines.toOwnedSlice(allocator);
}

pub fn maxLineWidth(lines: []const []const Segment) usize {
    var max_width: usize = 0;
    for (lines) |line| {
        const line_width = totalCellLength(line);
        if (line_width > max_width) {
            max_width = line_width;
        }
    }
    return max_width;
}

pub fn adjustLineLength(segments: []const Segment, target_length: usize, pad_char: u8, allocator: std.mem.Allocator) ![]Segment {
    const current_len = totalCellLength(segments);

    if (current_len == target_length) {
        return try allocator.dupe(Segment, segments);
    }

    var result: std.ArrayList(Segment) = .empty;

    if (current_len < target_length) {
        try result.appendSlice(allocator, segments);
        const padding = target_length - current_len;
        const pad_str = try allocator.alloc(u8, padding);
        @memset(pad_str, pad_char);
        try result.append(allocator, Segment.plain(pad_str));
    } else {
        var remaining = target_length;
        for (segments) |seg| {
            if (seg.control != null) {
                try result.append(allocator, seg);
                continue;
            }

            const seg_len = seg.cellLength();
            if (seg_len <= remaining) {
                try result.append(allocator, seg);
                remaining -= seg_len;
            } else if (remaining > 0) {
                const split = seg.splitCells(remaining);
                try result.append(allocator, split[0]);
                remaining = 0;
                break;
            } else {
                break;
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

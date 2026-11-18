const std = @import("std");
const Style = @import("style.zig").Style;
const Segment = @import("segment.zig").Segment;
const markup = @import("markup.zig");
const cells = @import("cells.zig");
const Theme = @import("theme.zig").Theme;

pub const Span = struct {
    start: usize,
    end: usize,
    style: Style,
};

pub const Text = struct {
    plain: []const u8,
    spans: []const Span,
    style: Style,
    allocator: std.mem.Allocator,
    owns_plain: bool = false,
    owns_spans: bool = false,

    pub fn init(allocator: std.mem.Allocator) Text {
        return .{
            .plain = "",
            .spans = &[_]Span{},
            .style = Style.empty,
            .allocator = allocator,
        };
    }

    pub fn fromPlain(allocator: std.mem.Allocator, text: []const u8) Text {
        return .{
            .plain = text,
            .spans = &[_]Span{},
            .style = Style.empty,
            .allocator = allocator,
        };
    }

    pub fn fromPlainOwned(allocator: std.mem.Allocator, text: []const u8) !Text {
        const owned = try allocator.dupe(u8, text);
        return .{
            .plain = owned,
            .spans = &[_]Span{},
            .style = Style.empty,
            .allocator = allocator,
            .owns_plain = true,
        };
    }

    pub fn fromMarkup(allocator: std.mem.Allocator, text: []const u8) !Text {
        const tokens = try markup.parseMarkup(text, allocator);
        defer allocator.free(tokens);

        var plain_buf: std.ArrayList(u8) = .empty;
        defer plain_buf.deinit(allocator);

        var spans_buf: std.ArrayList(Span) = .empty;
        defer spans_buf.deinit(allocator);

        var style_stack: std.ArrayList(Style) = .empty;
        defer style_stack.deinit(allocator);
        try style_stack.append(allocator, Style.empty);

        for (tokens) |token| {
            switch (token) {
                .text => |txt| {
                    const start = plain_buf.items.len;
                    try plain_buf.appendSlice(allocator, txt);
                    const end = plain_buf.items.len;

                    const current_style = style_stack.getLast();
                    if (!current_style.isEmpty()) {
                        try spans_buf.append(allocator, .{
                            .start = start,
                            .end = end,
                            .style = current_style,
                        });
                    }
                },
                .open_tag => |tag| {
                    const current_style = style_stack.getLast();
                    const new_style = Style.parse(tag.name) catch continue;
                    try style_stack.append(allocator, current_style.combine(new_style));
                },
                .close_tag => {
                    if (style_stack.items.len > 1) {
                        _ = style_stack.pop();
                    }
                },
            }
        }

        return .{
            .plain = try plain_buf.toOwnedSlice(allocator),
            .spans = try spans_buf.toOwnedSlice(allocator),
            .style = Style.empty,
            .allocator = allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn fromMarkupWithTheme(allocator: std.mem.Allocator, text: []const u8, theme: Theme) !Text {
        const tokens = try markup.parseMarkup(text, allocator);
        defer allocator.free(tokens);

        var plain_buf: std.ArrayList(u8) = .empty;
        defer plain_buf.deinit(allocator);

        var spans_buf: std.ArrayList(Span) = .empty;
        defer spans_buf.deinit(allocator);

        var style_stack: std.ArrayList(Style) = .empty;
        defer style_stack.deinit(allocator);
        try style_stack.append(allocator, Style.empty);

        for (tokens) |token| {
            switch (token) {
                .text => |txt| {
                    const start = plain_buf.items.len;
                    try plain_buf.appendSlice(allocator, txt);
                    const end = plain_buf.items.len;

                    const current_style = style_stack.getLast();
                    if (!current_style.isEmpty()) {
                        try spans_buf.append(allocator, .{
                            .start = start,
                            .end = end,
                            .style = current_style,
                        });
                    }
                },
                .open_tag => |tag| {
                    const current_style = style_stack.getLast();
                    const new_style = theme.get(tag.name) orelse
                        (Style.parse(tag.name) catch continue);
                    try style_stack.append(allocator, current_style.combine(new_style));
                },
                .close_tag => {
                    if (style_stack.items.len > 1) {
                        _ = style_stack.pop();
                    }
                },
            }
        }

        return .{
            .plain = try plain_buf.toOwnedSlice(allocator),
            .spans = try spans_buf.toOwnedSlice(allocator),
            .style = Style.empty,
            .allocator = allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn deinit(self: *Text) void {
        if (self.owns_spans and self.spans.len > 0) {
            self.allocator.free(self.spans);
        }
        if (self.owns_plain and self.plain.len > 0) {
            self.allocator.free(@constCast(self.plain));
        }
        self.* = undefined;
    }

    pub fn cellLength(self: Text) usize {
        return cells.cellLen(self.plain);
    }

    pub fn len(self: Text) usize {
        return self.plain.len;
    }

    pub fn isEmpty(self: Text) bool {
        return self.plain.len == 0;
    }

    pub fn render(self: Text, allocator: std.mem.Allocator) ![]Segment {
        if (self.spans.len == 0) {
            const result = try allocator.alloc(Segment, 1);
            result[0] = Segment.styledOptional(self.plain, if (self.style.isEmpty()) null else self.style);
            return result;
        }

        var segments: std.ArrayList(Segment) = .empty;
        var pos: usize = 0;

        for (self.spans) |span| {
            if (span.start > pos) {
                try segments.append(allocator, Segment.styledOptional(
                    self.plain[pos..span.start],
                    if (self.style.isEmpty()) null else self.style,
                ));
            }
            const combined = self.style.combine(span.style);
            try segments.append(allocator, Segment.styled(
                self.plain[span.start..span.end],
                combined,
            ));
            pos = span.end;
        }

        if (pos < self.plain.len) {
            try segments.append(allocator, Segment.styledOptional(
                self.plain[pos..],
                if (self.style.isEmpty()) null else self.style,
            ));
        }

        return segments.toOwnedSlice(allocator);
    }

    pub fn withStyle(self: Text, new_style: Style) Text {
        return .{
            .plain = self.plain,
            .spans = self.spans,
            .style = new_style,
            .allocator = self.allocator,
            .owns_plain = false, // Don't take ownership when creating derivative
            .owns_spans = false,
        };
    }

    pub fn append(self: *Text, other: Text) !void {
        const offset = self.plain.len;

        const new_plain = try self.allocator.alloc(u8, self.plain.len + other.plain.len);
        @memcpy(new_plain[0..self.plain.len], self.plain);
        @memcpy(new_plain[self.plain.len..], other.plain);

        const new_spans = try self.allocator.alloc(Span, self.spans.len + other.spans.len);
        @memcpy(new_spans[0..self.spans.len], self.spans);
        for (other.spans, 0..) |span, i| {
            new_spans[self.spans.len + i] = .{
                .start = span.start + offset,
                .end = span.end + offset,
                .style = span.style,
            };
        }

        if (self.owns_plain and self.plain.len > 0) {
            self.allocator.free(@constCast(self.plain));
        }
        if (self.owns_spans and self.spans.len > 0) {
            self.allocator.free(self.spans);
        }

        self.plain = new_plain;
        self.spans = new_spans;
        self.owns_plain = true;
        self.owns_spans = true;
    }

    pub fn slice(self: Text, start: usize, end: usize) Text {
        const actual_end = @min(end, self.plain.len);
        const actual_start = @min(start, actual_end);

        var relevant_spans: std.ArrayList(Span) = .empty;
        for (self.spans) |span| {
            if (span.end > actual_start and span.start < actual_end) {
                relevant_spans.append(self.allocator, .{
                    .start = if (span.start < actual_start) 0 else span.start - actual_start,
                    .end = @min(span.end, actual_end) - actual_start,
                    .style = span.style,
                }) catch {};
            }
        }

        // Capture count before toOwnedSlice (which sets items.len to 0)
        const has_spans = relevant_spans.items.len > 0;

        return .{
            .plain = self.plain[actual_start..actual_end],
            .spans = relevant_spans.toOwnedSlice(self.allocator) catch &[_]Span{},
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = false,
            .owns_spans = has_spans,
        };
    }

    pub fn highlight(self: *Text, start: usize, end: usize, style: Style) !void {
        const actual_end = @min(end, self.plain.len);
        const actual_start = @min(start, actual_end);

        var new_spans = try self.allocator.alloc(Span, self.spans.len + 1);
        @memcpy(new_spans[0..self.spans.len], self.spans);
        new_spans[self.spans.len] = .{
            .start = actual_start,
            .end = actual_end,
            .style = style,
        };

        if (self.owns_spans and self.spans.len > 0) {
            self.allocator.free(self.spans);
        }

        self.spans = new_spans;
        self.owns_spans = true;
    }

    pub fn clone(self: Text) !Text {
        const new_plain = try self.allocator.dupe(u8, self.plain);
        errdefer self.allocator.free(new_plain);

        const new_spans = try self.allocator.dupe(Span, self.spans);

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn truncate(self: Text, max_cells: usize, ellipsis: []const u8) !Text {
        const current_len = self.cellLength();
        if (current_len <= max_cells) {
            return self.clone();
        }

        const ellipsis_width = cells.cellLen(ellipsis);
        if (max_cells <= ellipsis_width) {
            const cutoff = cells.cellToByteIndex(self.plain, max_cells);
            return self.truncateAtByte(cutoff, "");
        }

        const target_cells = max_cells - ellipsis_width;
        const cutoff = cells.cellToByteIndex(self.plain, target_cells);
        return self.truncateAtByte(cutoff, ellipsis);
    }

    fn truncateAtByte(self: Text, cutoff: usize, ellipsis: []const u8) !Text {
        const new_plain = try self.allocator.alloc(u8, cutoff + ellipsis.len);
        errdefer self.allocator.free(new_plain);
        @memcpy(new_plain[0..cutoff], self.plain[0..cutoff]);
        @memcpy(new_plain[cutoff..], ellipsis);

        var span_count: usize = 0;
        for (self.spans) |span| {
            if (span.start < cutoff) span_count += 1;
        }

        const new_spans = try self.allocator.alloc(Span, span_count);
        errdefer self.allocator.free(new_spans);

        var i: usize = 0;
        for (self.spans) |span| {
            if (span.start < cutoff) {
                new_spans[i] = .{
                    .start = span.start,
                    .end = @min(span.end, cutoff),
                    .style = span.style,
                };
                i += 1;
            }
        }

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn alignLeft(self: Text, width: usize) !Text {
        const current_len = self.cellLength();
        if (current_len >= width) {
            return self.clone();
        }

        const padding = width - current_len;
        const new_plain = try self.allocator.alloc(u8, self.plain.len + padding);
        errdefer self.allocator.free(new_plain);
        @memcpy(new_plain[0..self.plain.len], self.plain);
        @memset(new_plain[self.plain.len..], ' ');

        const new_spans = try self.allocator.dupe(Span, self.spans);

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn alignRight(self: Text, width: usize) !Text {
        const current_len = self.cellLength();
        if (current_len >= width) {
            return self.clone();
        }

        const padding = width - current_len;
        const new_plain = try self.allocator.alloc(u8, self.plain.len + padding);
        errdefer self.allocator.free(new_plain);
        @memset(new_plain[0..padding], ' ');
        @memcpy(new_plain[padding..], self.plain);

        const new_spans = try self.allocator.alloc(Span, self.spans.len);
        errdefer self.allocator.free(new_spans);
        for (self.spans, 0..) |span, i| {
            new_spans[i] = .{
                .start = span.start + padding,
                .end = span.end + padding,
                .style = span.style,
            };
        }

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn alignCenter(self: Text, width: usize) !Text {
        const current_len = self.cellLength();
        if (current_len >= width) {
            return self.clone();
        }

        const total_padding = width - current_len;
        const left_padding = total_padding / 2;

        const new_plain = try self.allocator.alloc(u8, self.plain.len + total_padding);
        errdefer self.allocator.free(new_plain);
        @memset(new_plain[0..left_padding], ' ');
        @memcpy(new_plain[left_padding .. left_padding + self.plain.len], self.plain);
        @memset(new_plain[left_padding + self.plain.len ..], ' ');

        const new_spans = try self.allocator.alloc(Span, self.spans.len);
        errdefer self.allocator.free(new_spans);
        for (self.spans, 0..) |span, i| {
            new_spans[i] = .{
                .start = span.start + left_padding,
                .end = span.end + left_padding,
                .style = span.style,
            };
        }

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn wrap(self: Text, max_width: usize) ![]Text {
        if (max_width == 0) {
            const result = try self.allocator.alloc(Text, 0);
            return result;
        }

        var lines: std.ArrayList(Text) = .empty;
        errdefer {
            for (lines.items) |*line| line.deinit();
            lines.deinit(self.allocator);
        }

        var line_start: usize = 0; // byte position
        var line_start_cell: usize = 0; // cell position for span adjustment
        var current_cell: usize = 0;
        var last_space_byte: ?usize = null;
        var last_space_cell: ?usize = null;
        var i: usize = 0;

        while (i < self.plain.len) {
            const byte = self.plain[i];
            const cp_len = std.unicode.utf8ByteSequenceLength(byte) catch {
                i += 1;
                continue;
            };

            if (i + cp_len > self.plain.len) break;

            const cp = std.unicode.utf8Decode(self.plain[i..][0..cp_len]) catch {
                i += 1;
                continue;
            };

            const char_width = cells.getCharacterCellSize(cp);

            if (cp == ' ') {
                last_space_byte = i;
                last_space_cell = current_cell;
            }

            current_cell += char_width;
            i += cp_len;

            if (current_cell - line_start_cell > max_width) {
                var break_byte: usize = undefined;
                var break_cell: usize = undefined;

                if (last_space_byte != null and last_space_byte.? > line_start) {
                    break_byte = last_space_byte.?;
                    break_cell = last_space_cell.?;
                } else {
                    break_byte = i - cp_len;
                    break_cell = current_cell - char_width;
                }

                const line = try self.createLineSlice(line_start, break_byte);
                try lines.append(self.allocator, line);

                if (last_space_byte != null and last_space_byte.? > line_start and break_byte == last_space_byte.?) {
                    line_start = break_byte + 1;
                    line_start_cell = break_cell + 1;
                } else {
                    line_start = break_byte;
                    line_start_cell = break_cell;
                }

                last_space_byte = null;
                last_space_cell = null;
            }
        }

        if (line_start < self.plain.len) {
            const line = try self.createLineSlice(line_start, self.plain.len);
            try lines.append(self.allocator, line);
        }

        if (lines.items.len == 0) {
            const empty_line = try self.clone();
            try lines.append(self.allocator, empty_line);
        }

        return lines.toOwnedSlice(self.allocator);
    }

    fn createLineSlice(self: Text, start_byte: usize, end_byte: usize) !Text {
        const line_text = self.plain[start_byte..end_byte];
        const new_plain = try self.allocator.dupe(u8, line_text);
        errdefer self.allocator.free(new_plain);

        var span_count: usize = 0;
        for (self.spans) |span| {
            if (span.end > start_byte and span.start < end_byte) span_count += 1;
        }

        const new_spans = try self.allocator.alloc(Span, span_count);
        errdefer self.allocator.free(new_spans);

        var idx: usize = 0;
        for (self.spans) |span| {
            if (span.end > start_byte and span.start < end_byte) {
                const adj_start = if (span.start < start_byte) 0 else span.start - start_byte;
                const adj_end = @min(span.end, end_byte) - start_byte;
                new_spans[idx] = .{
                    .start = adj_start,
                    .end = adj_end,
                    .style = span.style,
                };
                idx += 1;
            }
        }

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn justify(self: Text, width: usize) !Text {
        const current_len = self.cellLength();
        if (current_len >= width) {
            return self.clone();
        }

        var word_count: usize = 0;
        var in_word = false;
        for (self.plain) |c| {
            if (c == ' ') {
                in_word = false;
            } else if (!in_word) {
                word_count += 1;
                in_word = true;
            }
        }

        if (word_count <= 1) {
            return self.alignLeft(width);
        }

        const gaps = word_count - 1;
        const extra_spaces = width - current_len;
        const base_extra = extra_spaces / gaps;
        const remainder = extra_spaces % gaps;

        var new_plain: std.ArrayList(u8) = .empty;
        errdefer new_plain.deinit(self.allocator);

        var position_map: std.ArrayList(usize) = .empty;
        defer position_map.deinit(self.allocator);

        var gap_index: usize = 0;
        in_word = false;
        var i: usize = 0;

        while (i < self.plain.len) {
            const c = self.plain[i];
            try position_map.append(self.allocator, new_plain.items.len);

            if (c == ' ') {
                try new_plain.append(self.allocator, ' ');
                if (in_word) {
                    const extra = base_extra + (if (gap_index < remainder) @as(usize, 1) else 0);
                    for (0..extra) |_| {
                        try new_plain.append(self.allocator, ' ');
                    }
                    gap_index += 1;
                }
                in_word = false;
            } else {
                try new_plain.append(self.allocator, c);
                in_word = true;
            }
            i += 1;
        }

        try position_map.append(self.allocator, new_plain.items.len);

        const new_spans = try self.allocator.alloc(Span, self.spans.len);
        errdefer self.allocator.free(new_spans);

        for (self.spans, 0..) |span, idx| {
            const new_start = if (span.start < position_map.items.len) position_map.items[span.start] else new_plain.items.len;
            const new_end = if (span.end < position_map.items.len) position_map.items[span.end] else new_plain.items.len;
            new_spans[idx] = .{
                .start = new_start,
                .end = new_end,
                .style = span.style,
            };
        }

        return .{
            .plain = try new_plain.toOwnedSlice(self.allocator),
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }

    pub fn highlightPattern(self: Text, pattern: []const u8, style: Style) !Text {
        if (pattern.len == 0) {
            return self.clone();
        }

        var matches: std.ArrayList(usize) = .empty;
        defer matches.deinit(self.allocator);

        var pos: usize = 0;
        while (pos + pattern.len <= self.plain.len) {
            if (std.mem.indexOf(u8, self.plain[pos..], pattern)) |idx| {
                try matches.append(self.allocator, pos + idx);
                pos = pos + idx + 1; // Allow overlapping matches
            } else {
                break;
            }
        }

        if (matches.items.len == 0) {
            return self.clone();
        }

        const new_plain = try self.allocator.dupe(u8, self.plain);
        errdefer self.allocator.free(new_plain);

        const new_spans = try self.allocator.alloc(Span, self.spans.len + matches.items.len);
        errdefer self.allocator.free(new_spans);

        @memcpy(new_spans[0..self.spans.len], self.spans);

        for (matches.items, 0..) |match_pos, i| {
            new_spans[self.spans.len + i] = .{
                .start = match_pos,
                .end = match_pos + pattern.len,
                .style = style,
            };
        }

        return .{
            .plain = new_plain,
            .spans = new_spans,
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = true,
            .owns_spans = true,
        };
    }
};

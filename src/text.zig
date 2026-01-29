const std = @import("std");
const Style = @import("style.zig").Style;
const Segment = @import("segment.zig").Segment;
const markup = @import("markup.zig");
const cells = @import("cells.zig");

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

                    const current_style = style_stack.items[style_stack.items.len - 1];
                    if (!current_style.isEmpty()) {
                        try spans_buf.append(allocator, .{
                            .start = start,
                            .end = end,
                            .style = current_style,
                        });
                    }
                },
                .open_tag => |tag| {
                    const current_style = style_stack.items[style_stack.items.len - 1];
                    const new_style = Style.parse(tag.name) catch {
                        // If parsing fails, ignore the tag
                        continue;
                    };
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
            // Text before span (unstyled or with base style)
            if (span.start > pos) {
                try segments.append(allocator, Segment.styledOptional(
                    self.plain[pos..span.start],
                    if (self.style.isEmpty()) null else self.style,
                ));
            }
            // Span text with combined style
            const combined = self.style.combine(span.style);
            try segments.append(allocator, Segment.styled(
                self.plain[span.start..span.end],
                combined,
            ));
            pos = span.end;
        }

        // Remaining text after last span
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

        // Create new plain text
        const new_plain = try self.allocator.alloc(u8, self.plain.len + other.plain.len);
        @memcpy(new_plain[0..self.plain.len], self.plain);
        @memcpy(new_plain[self.plain.len..], other.plain);

        // Create new spans with offset adjustment
        const new_spans = try self.allocator.alloc(Span, self.spans.len + other.spans.len);
        @memcpy(new_spans[0..self.spans.len], self.spans);
        for (other.spans, 0..) |span, i| {
            new_spans[self.spans.len + i] = .{
                .start = span.start + offset,
                .end = span.end + offset,
                .style = span.style,
            };
        }

        // Free old data if owned
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

        // Filter and adjust spans
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

        return .{
            .plain = self.plain[actual_start..actual_end],
            .spans = relevant_spans.toOwnedSlice(self.allocator) catch &[_]Span{},
            .style = self.style,
            .allocator = self.allocator,
            .owns_plain = false,
            .owns_spans = relevant_spans.items.len > 0,
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
};

// Tests
test "Text.init" {
    const allocator = std.testing.allocator;
    var text = Text.init(allocator);
    defer text.deinit();

    try std.testing.expectEqual(@as(usize, 0), text.len());
    try std.testing.expect(text.isEmpty());
}

test "Text.fromPlain" {
    const allocator = std.testing.allocator;
    const text = Text.fromPlain(allocator, "Hello");

    try std.testing.expectEqualStrings("Hello", text.plain);
    try std.testing.expectEqual(@as(usize, 5), text.len());
    try std.testing.expectEqual(@as(usize, 5), text.cellLength());
}

test "Text.fromMarkup basic" {
    const allocator = std.testing.allocator;
    var text = try Text.fromMarkup(allocator, "[bold]Hello[/]");
    defer text.deinit();

    try std.testing.expectEqualStrings("Hello", text.plain);
    try std.testing.expectEqual(@as(usize, 1), text.spans.len);
    try std.testing.expect(text.spans[0].style.hasAttribute(.bold));
}

test "Text.fromMarkup nested" {
    const allocator = std.testing.allocator;
    var text = try Text.fromMarkup(allocator, "[bold][red]Hello[/][/]");
    defer text.deinit();

    try std.testing.expectEqualStrings("Hello", text.plain);
    try std.testing.expectEqual(@as(usize, 1), text.spans.len);
    try std.testing.expect(text.spans[0].style.hasAttribute(.bold));
}

test "Text.fromMarkup mixed" {
    const allocator = std.testing.allocator;
    var text = try Text.fromMarkup(allocator, "Hello [bold]World[/]!");
    defer text.deinit();

    try std.testing.expectEqualStrings("Hello World!", text.plain);
    try std.testing.expectEqual(@as(usize, 1), text.spans.len);
    try std.testing.expectEqual(@as(usize, 6), text.spans[0].start);
    try std.testing.expectEqual(@as(usize, 11), text.spans[0].end);
}

test "Text.render" {
    const allocator = std.testing.allocator;
    var text = try Text.fromMarkup(allocator, "[bold]Hello[/] World");
    defer text.deinit();

    const segments = try text.render(allocator);
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 2), segments.len);
    try std.testing.expectEqualStrings("Hello", segments[0].text);
    try std.testing.expect(segments[0].style.?.hasAttribute(.bold));
    try std.testing.expectEqualStrings(" World", segments[1].text);
}

test "Text.cellLength with CJK" {
    const allocator = std.testing.allocator;
    const text = Text.fromPlain(allocator, "\u{4E2D}\u{6587}");

    try std.testing.expectEqual(@as(usize, 4), text.cellLength()); // 2 CJK = 4 cells
}

test "Text.append" {
    const allocator = std.testing.allocator;
    var text1 = try Text.fromMarkup(allocator, "[bold]Hello[/]");
    defer text1.deinit();

    const text2 = Text.fromPlain(allocator, " World");

    try text1.append(text2);

    try std.testing.expectEqualStrings("Hello World", text1.plain);
    try std.testing.expectEqual(@as(usize, 1), text1.spans.len);
    try std.testing.expectEqual(@as(usize, 0), text1.spans[0].start);
    try std.testing.expectEqual(@as(usize, 5), text1.spans[0].end);
}

test "Text.withStyle" {
    const allocator = std.testing.allocator;
    const base = Text.fromPlain(allocator, "Hello");
    const styled = base.withStyle(Style.empty.bold());

    const segments = try styled.render(allocator);
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expect(segments[0].style.?.hasAttribute(.bold));
}

test "Text.highlight" {
    const allocator = std.testing.allocator;
    var text = Text.fromPlain(allocator, "Hello World");

    try text.highlight(6, 11, Style.empty.bold());
    defer {
        if (text.owns_spans) allocator.free(text.spans);
    }

    try std.testing.expectEqual(@as(usize, 1), text.spans.len);
    try std.testing.expectEqual(@as(usize, 6), text.spans[0].start);
    try std.testing.expectEqual(@as(usize, 11), text.spans[0].end);
}

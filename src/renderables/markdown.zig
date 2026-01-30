const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const Color = @import("../color.zig").Color;
const cells = @import("../cells.zig");

pub const HeaderLevel = enum(u3) {
    h1 = 1,
    h2 = 2,
    h3 = 3,
    h4 = 4,
    h5 = 5,
    h6 = 6,

    pub fn fromCount(count: usize) ?HeaderLevel {
        return switch (count) {
            1 => .h1,
            2 => .h2,
            3 => .h3,
            4 => .h4,
            5 => .h5,
            6 => .h6,
            else => null,
        };
    }
};

pub const MarkdownTheme = struct {
    h1_style: Style = Style.empty.bold().fg(Color.bright_cyan),
    h2_style: Style = Style.empty.bold().fg(Color.bright_blue),
    h3_style: Style = Style.empty.bold().fg(Color.bright_magenta),
    h4_style: Style = Style.empty.bold().fg(Color.cyan),
    h5_style: Style = Style.empty.bold().fg(Color.blue),
    h6_style: Style = Style.empty.bold().fg(Color.magenta).dim(),
    h1_underline: ?[]const u8 = "\u{2550}",
    h2_underline: ?[]const u8 = "\u{2500}",
    bold_style: Style = Style.empty.bold(),
    italic_style: Style = Style.empty.italic(),
    bold_italic_style: Style = Style.empty.bold().italic(),

    pub const default: MarkdownTheme = .{};

    pub fn styleForLevel(self: MarkdownTheme, level: HeaderLevel) Style {
        return switch (level) {
            .h1 => self.h1_style,
            .h2 => self.h2_style,
            .h3 => self.h3_style,
            .h4 => self.h4_style,
            .h5 => self.h5_style,
            .h6 => self.h6_style,
        };
    }

    pub fn underlineForLevel(self: MarkdownTheme, level: HeaderLevel) ?[]const u8 {
        return switch (level) {
            .h1 => self.h1_underline,
            .h2 => self.h2_underline,
            else => null,
        };
    }
};

pub const Header = struct {
    text: []const u8,
    level: HeaderLevel,
    theme: MarkdownTheme = .default,
    width: ?usize = null,

    pub fn init(text: []const u8, level: HeaderLevel) Header {
        return .{ .text = text, .level = level };
    }

    pub fn h1(text: []const u8) Header {
        return init(text, .h1);
    }

    pub fn h2(text: []const u8) Header {
        return init(text, .h2);
    }

    pub fn h3(text: []const u8) Header {
        return init(text, .h3);
    }

    pub fn h4(text: []const u8) Header {
        return init(text, .h4);
    }

    pub fn h5(text: []const u8) Header {
        return init(text, .h5);
    }

    pub fn h6(text: []const u8) Header {
        return init(text, .h6);
    }

    pub fn withTheme(self: Header, theme: MarkdownTheme) Header {
        var h = self;
        h.theme = theme;
        return h;
    }

    pub fn withWidth(self: Header, w: usize) Header {
        var h = self;
        h.width = w;
        return h;
    }

    pub fn render(self: Header, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        const style = self.theme.styleForLevel(self.level);
        const text_width = cells.cellLen(self.text);
        const effective_width = self.width orelse max_width;

        try segments.append(allocator, Segment.styled(self.text, style));
        try segments.append(allocator, Segment.line());

        if (self.theme.underlineForLevel(self.level)) |underline_char| {
            const underline_len = @min(text_width, effective_width);
            const char_width = cells.cellLen(underline_char);

            if (char_width > 0) {
                const repeat_count = underline_len / char_width;
                for (0..repeat_count) |_| {
                    try segments.append(allocator, Segment.styled(underline_char, style));
                }
            }
            try segments.append(allocator, Segment.line());
        }

        return segments.toOwnedSlice(allocator);
    }
};

pub const Markdown = struct {
    source: []const u8,
    theme: MarkdownTheme = .default,

    pub fn init(source: []const u8) Markdown {
        return .{ .source = source };
    }

    pub fn withTheme(self: Markdown, theme: MarkdownTheme) Markdown {
        var m = self;
        m.theme = theme;
        return m;
    }

    pub fn render(self: Markdown, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;
        var lines = std.mem.splitScalar(u8, self.source, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, " \t");

            if (parseHeader(trimmed)) |header_info| {
                const header = Header.init(header_info.text, header_info.level)
                    .withTheme(self.theme);
                const header_segments = try header.render(max_width, allocator);
                defer allocator.free(header_segments);
                try segments.appendSlice(allocator, header_segments);
            } else {
                if (line.len > 0) {
                    try self.renderInlineText(line, null, &segments, allocator);
                }
                try segments.append(allocator, Segment.line());
            }
        }

        return segments.toOwnedSlice(allocator);
    }

    const HeaderInfo = struct {
        level: HeaderLevel,
        text: []const u8,
    };

    fn parseHeader(line: []const u8) ?HeaderInfo {
        if (line.len == 0 or line[0] != '#') return null;

        var hash_count: usize = 0;
        while (hash_count < line.len and line[hash_count] == '#') {
            hash_count += 1;
        }

        const level = HeaderLevel.fromCount(hash_count) orelse return null;

        if (hash_count >= line.len) {
            return .{ .level = level, .text = "" };
        }

        if (line[hash_count] != ' ' and line[hash_count] != '\t') {
            return null;
        }

        const text = std.mem.trim(u8, line[hash_count..], " \t");
        return .{ .level = level, .text = text };
    }

    const InlineSpan = struct {
        text: []const u8,
        style_type: StyleType,

        const StyleType = enum {
            plain,
            bold,
            italic,
            bold_italic,
        };
    };

    fn parseInlineStyles(text: []const u8, allocator: std.mem.Allocator) ![]InlineSpan {
        var spans: std.ArrayList(InlineSpan) = .empty;
        var pos: usize = 0;

        while (pos < text.len) {
            if (tryParseStyledSpan(text, pos)) |result| {
                try spans.append(allocator, .{
                    .text = result.content,
                    .style_type = result.style_type,
                });
                pos = result.end_pos;
                continue;
            }

            // Plain text - find next potential delimiter or end
            const plain_start = pos;
            pos = advanceToNextDelimiter(text, pos);

            // If we hit an unmatched delimiter, skip it and continue
            if (pos < text.len and plain_start == pos) {
                pos += 1;
                pos = advanceToNextDelimiter(text, pos);
            }

            if (pos > plain_start) {
                try spans.append(allocator, .{
                    .text = text[plain_start..pos],
                    .style_type = .plain,
                });
            }
        }

        return spans.toOwnedSlice(allocator);
    }

    const ParseResult = struct {
        content: []const u8,
        style_type: InlineSpan.StyleType,
        end_pos: usize,
    };

    fn tryParseStyledSpan(text: []const u8, pos: usize) ?ParseResult {
        const c = text[pos];
        if (c != '*' and c != '_') return null;

        // Try longest match first (bold+italic: 3, bold: 2, italic: 1)
        const patterns = [_]struct { count: usize, style: InlineSpan.StyleType }{
            .{ .count = 3, .style = .bold_italic },
            .{ .count = 2, .style = .bold },
            .{ .count = 1, .style = .italic },
        };

        for (patterns) |p| {
            if (pos + p.count > text.len) continue;
            if (!isRepeatedChar(text[pos..][0..p.count], c)) continue;
            if (findClosingDelimiter(text, pos + p.count, c, p.count)) |end| {
                return .{
                    .content = text[pos + p.count .. end],
                    .style_type = p.style,
                    .end_pos = end + p.count,
                };
            }
        }
        return null;
    }

    fn isRepeatedChar(slice: []const u8, char: u8) bool {
        for (slice) |c| {
            if (c != char) return false;
        }
        return true;
    }

    fn advanceToNextDelimiter(text: []const u8, start: usize) usize {
        var pos = start;
        while (pos < text.len and text[pos] != '*' and text[pos] != '_') {
            pos += 1;
        }
        return pos;
    }

    fn findClosingDelimiter(text: []const u8, start: usize, delimiter: u8, count: usize) ?usize {
        if (start >= text.len) return null;

        var pos = start;
        while (pos + count <= text.len) : (pos += 1) {
            const slice = text[pos..][0..count];
            const all_match = for (slice) |c| {
                if (c != delimiter) break false;
            } else true;

            if (!all_match) continue;

            const before_ok = pos == start or text[pos - 1] != delimiter;
            const after_ok = pos + count >= text.len or text[pos + count] != delimiter;
            if (before_ok and after_ok) return pos;
        }
        return null;
    }

    fn renderInlineText(
        self: Markdown,
        text: []const u8,
        base_style: ?Style,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        const spans = try parseInlineStyles(text, allocator);
        defer allocator.free(spans);

        for (spans) |span| {
            const inline_style: ?Style = switch (span.style_type) {
                .plain => null,
                .bold => self.theme.bold_style,
                .italic => self.theme.italic_style,
                .bold_italic => self.theme.bold_italic_style,
            };

            const final_style: ?Style = if (inline_style) |is|
                if (base_style) |bs| bs.combine(is) else is
            else
                base_style;

            if (final_style) |s| {
                try segments.append(allocator, Segment.styled(span.text, s));
            } else {
                try segments.append(allocator, Segment.plain(span.text));
            }
        }
    }
};

// Tests
test "HeaderLevel.fromCount" {
    try std.testing.expectEqual(HeaderLevel.h1, HeaderLevel.fromCount(1).?);
    try std.testing.expectEqual(HeaderLevel.h6, HeaderLevel.fromCount(6).?);
    try std.testing.expect(HeaderLevel.fromCount(0) == null);
    try std.testing.expect(HeaderLevel.fromCount(7) == null);
}

test "Header.h1 creates correct level" {
    const header = Header.h1("Title");
    try std.testing.expectEqual(HeaderLevel.h1, header.level);
    try std.testing.expectEqualStrings("Title", header.text);
}

test "Header.render h1 with underline" {
    const allocator = std.testing.allocator;
    const header = Header.h1("Title");
    const segments = try header.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expect(segments.len >= 2);
    try std.testing.expectEqualStrings("Title", segments[0].text);
    try std.testing.expect(segments[0].style != null);
    try std.testing.expect(segments[0].style.?.hasAttribute(.bold));
}

test "Header.render h3 no underline" {
    const allocator = std.testing.allocator;
    const header = Header.h3("Section");
    const segments = try header.render(80, allocator);
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 2), segments.len);
    try std.testing.expectEqualStrings("Section", segments[0].text);
    try std.testing.expectEqualStrings("\n", segments[1].text);
}

test "MarkdownTheme.styleForLevel returns distinct styles" {
    const theme = MarkdownTheme.default;
    const h1_style = theme.styleForLevel(.h1);
    const h6_style = theme.styleForLevel(.h6);

    try std.testing.expect(h1_style.hasAttribute(.bold));
    try std.testing.expect(h6_style.hasAttribute(.bold));
    try std.testing.expect(!h1_style.eql(h6_style));
}

test "Markdown.parseHeader valid headers" {
    const h1 = Markdown.parseHeader("# Title");
    try std.testing.expect(h1 != null);
    try std.testing.expectEqual(HeaderLevel.h1, h1.?.level);
    try std.testing.expectEqualStrings("Title", h1.?.text);

    const h3 = Markdown.parseHeader("### Section Name");
    try std.testing.expect(h3 != null);
    try std.testing.expectEqual(HeaderLevel.h3, h3.?.level);
    try std.testing.expectEqualStrings("Section Name", h3.?.text);
}

test "Markdown.parseHeader invalid headers" {
    try std.testing.expect(Markdown.parseHeader("Not a header") == null);
    try std.testing.expect(Markdown.parseHeader("#NoSpace") == null);
    try std.testing.expect(Markdown.parseHeader("####### Too many") == null);
    try std.testing.expect(Markdown.parseHeader("") == null);
}

test "Markdown.parseHeader edge cases" {
    const empty_h1 = Markdown.parseHeader("# ");
    try std.testing.expect(empty_h1 != null);
    try std.testing.expectEqualStrings("", empty_h1.?.text);

    const h6 = Markdown.parseHeader("###### Deep");
    try std.testing.expect(h6 != null);
    try std.testing.expectEqual(HeaderLevel.h6, h6.?.level);
}

test "Markdown.render parses headers" {
    const allocator = std.testing.allocator;
    const md = Markdown.init("# Main Title\n\nSome text\n\n## Subtitle");
    const segments = try md.render(80, allocator);
    defer allocator.free(segments);

    var found_main = false;
    var found_subtitle = false;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "Main Title")) {
            found_main = true;
            try std.testing.expect(seg.style != null);
        }
        if (std.mem.eql(u8, seg.text, "Subtitle")) {
            found_subtitle = true;
            try std.testing.expect(seg.style != null);
        }
    }
    try std.testing.expect(found_main);
    try std.testing.expect(found_subtitle);
}

test "Header all levels" {
    const allocator = std.testing.allocator;
    const levels = [_]HeaderLevel{ .h1, .h2, .h3, .h4, .h5, .h6 };

    for (levels) |level| {
        const header = Header.init("Test", level);
        const segments = try header.render(80, allocator);
        defer allocator.free(segments);

        try std.testing.expect(segments.len >= 2);
        try std.testing.expect(segments[0].style != null);
        try std.testing.expect(segments[0].style.?.hasAttribute(.bold));
    }
}

test "parseInlineStyles plain text" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 1), spans.len);
    try std.testing.expectEqualStrings("Hello world", spans[0].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.plain, spans[0].style_type);
}

test "parseInlineStyles single asterisk italic" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello *italic* world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("Hello ", spans[0].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.plain, spans[0].style_type);
    try std.testing.expectEqualStrings("italic", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.italic, spans[1].style_type);
    try std.testing.expectEqualStrings(" world", spans[2].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.plain, spans[2].style_type);
}

test "parseInlineStyles underscore italic" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello _italic_ world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("italic", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.italic, spans[1].style_type);
}

test "parseInlineStyles double asterisk bold" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello **bold** world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("bold", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.bold, spans[1].style_type);
}

test "parseInlineStyles double underscore bold" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello __bold__ world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("bold", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.bold, spans[1].style_type);
}

test "parseInlineStyles triple asterisk bold italic" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello ***bold italic*** world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("bold italic", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.bold_italic, spans[1].style_type);
}

test "parseInlineStyles triple underscore bold italic" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello ___bold italic___ world", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("bold italic", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.bold_italic, spans[1].style_type);
}

test "parseInlineStyles multiple styles in one line" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("*italic* and **bold**", allocator);
    defer allocator.free(spans);

    // Expected: italic, " and ", bold (no trailing text)
    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.italic, spans[0].style_type);
    try std.testing.expectEqualStrings("italic", spans[0].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.plain, spans[1].style_type);
    try std.testing.expectEqualStrings(" and ", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.bold, spans[2].style_type);
    try std.testing.expectEqualStrings("bold", spans[2].text);
}

test "parseInlineStyles at start of line" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("**bold** at start", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 2), spans.len);
    try std.testing.expectEqualStrings("bold", spans[0].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.bold, spans[0].style_type);
}

test "parseInlineStyles at end of line" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("end with *italic*", allocator);
    defer allocator.free(spans);

    try std.testing.expectEqual(@as(usize, 2), spans.len);
    try std.testing.expectEqualStrings("italic", spans[1].text);
    try std.testing.expectEqual(Markdown.InlineSpan.StyleType.italic, spans[1].style_type);
}

test "parseInlineStyles unclosed delimiter treated as plain" {
    const allocator = std.testing.allocator;
    const spans = try Markdown.parseInlineStyles("Hello *unclosed", allocator);
    defer allocator.free(spans);

    // Unclosed delimiter should be treated as plain text
    try std.testing.expect(spans.len >= 1);
    // The text should be preserved
    var total_len: usize = 0;
    for (spans) |span| {
        total_len += span.text.len;
    }
    try std.testing.expectEqual(@as(usize, 15), total_len);
}

test "Markdown.render with bold text" {
    const allocator = std.testing.allocator;
    const md = Markdown.init("This is **bold** text");
    const segments = try md.render(80, allocator);
    defer allocator.free(segments);

    var found_bold = false;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "bold")) {
            found_bold = true;
            try std.testing.expect(seg.style != null);
            try std.testing.expect(seg.style.?.hasAttribute(.bold));
        }
    }
    try std.testing.expect(found_bold);
}

test "Markdown.render with italic text" {
    const allocator = std.testing.allocator;
    const md = Markdown.init("This is *italic* text");
    const segments = try md.render(80, allocator);
    defer allocator.free(segments);

    var found_italic = false;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "italic")) {
            found_italic = true;
            try std.testing.expect(seg.style != null);
            try std.testing.expect(seg.style.?.hasAttribute(.italic));
        }
    }
    try std.testing.expect(found_italic);
}

test "Markdown.render with bold italic text" {
    const allocator = std.testing.allocator;
    const md = Markdown.init("This is ***bold italic*** text");
    const segments = try md.render(80, allocator);
    defer allocator.free(segments);

    var found_bold_italic = false;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "bold italic")) {
            found_bold_italic = true;
            try std.testing.expect(seg.style != null);
            try std.testing.expect(seg.style.?.hasAttribute(.bold));
            try std.testing.expect(seg.style.?.hasAttribute(.italic));
        }
    }
    try std.testing.expect(found_bold_italic);
}

test "MarkdownTheme has bold and italic styles" {
    const theme = MarkdownTheme.default;
    try std.testing.expect(theme.bold_style.hasAttribute(.bold));
    try std.testing.expect(theme.italic_style.hasAttribute(.italic));
    try std.testing.expect(theme.bold_italic_style.hasAttribute(.bold));
    try std.testing.expect(theme.bold_italic_style.hasAttribute(.italic));
}

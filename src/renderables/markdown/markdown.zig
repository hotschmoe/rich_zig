const std = @import("std");
const Segment = @import("../../segment.zig").Segment;
const Style = @import("../../style.zig").Style;
const syntax_mod = @import("../syntax/mod.zig");
const Syntax = syntax_mod.Syntax;
const SyntaxTheme = syntax_mod.SyntaxTheme;
const Language = syntax_mod.Language;
const Rule = @import("../rule.zig").Rule;
const table_mod = @import("../table/mod.zig");
const Table = table_mod.Table;
const Column = table_mod.Column;
const JustifyMethod = table_mod.JustifyMethod;
const theme_mod = @import("theme.zig");
const HeaderLevel = theme_mod.HeaderLevel;
const MarkdownTheme = theme_mod.MarkdownTheme;
const elements_mod = @import("elements.zig");
const Header = elements_mod.Header;
const CodeBlock = elements_mod.CodeBlock;

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

        var in_code_block = false;
        var code_block_lang: ?[]const u8 = null;
        var code_lines: std.ArrayList(u8) = .empty;

        var table_lines: std.ArrayList([]const u8) = .empty;
        defer table_lines.deinit(allocator);

        while (lines.next()) |line| {
            const trimmed = std.mem.trimStart(u8, line, " \t");

            if (parseFenceOpen(trimmed)) |lang| {
                if (!in_code_block) {
                    if (table_lines.items.len > 0) {
                        try self.emitTable(&table_lines, max_width, &segments, allocator);
                    }
                    in_code_block = true;
                    code_block_lang = lang;
                    code_lines = .empty;
                    continue;
                }
            }

            if (in_code_block) {
                if (parseFenceClose(trimmed)) {
                    try self.emitCodeBlock(&code_lines, code_block_lang, max_width, &segments, allocator);
                    in_code_block = false;
                    code_block_lang = null;
                    continue;
                }

                if (code_lines.items.len > 0) {
                    try code_lines.append(allocator, '\n');
                }
                try code_lines.appendSlice(allocator, line);
                continue;
            }

            if (isTableRow(trimmed)) {
                try table_lines.append(allocator, trimmed);
                continue;
            }

            if (table_lines.items.len > 0) {
                try self.emitTable(&table_lines, max_width, &segments, allocator);
            }

            if (parseHeader(trimmed)) |header_info| {
                const header = Header.init(header_info.text, header_info.level)
                    .withTheme(self.theme);
                const header_segments = try header.render(max_width, allocator);
                defer allocator.free(header_segments);
                try segments.appendSlice(allocator, header_segments);
            } else if (parseHorizontalRule(trimmed)) {
                const rule = Rule.init()
                    .withCharacters(self.theme.rule_char)
                    .withStyle(self.theme.rule_style);
                const rule_segments = try rule.render(max_width, allocator);
                defer allocator.free(rule_segments);
                try segments.appendSlice(allocator, rule_segments);
            } else if (parseBlockquote(line)) |blockquote| {
                try self.renderBlockquoteLine(blockquote, &segments, allocator);
                try segments.append(allocator, Segment.line());
            } else if (parseOrderedListItem(line)) |list_item| {
                try self.renderOrderedListItem(list_item, &segments, allocator);
                try segments.append(allocator, Segment.line());
            } else if (parseUnorderedListItem(line)) |list_item| {
                try self.renderUnorderedListItem(list_item, &segments, allocator);
                try segments.append(allocator, Segment.line());
            } else {
                if (line.len > 0) {
                    try self.renderInlineText(line, null, &segments, allocator);
                }
                try segments.append(allocator, Segment.line());
            }
        }

        if (in_code_block and code_lines.items.len > 0) {
            try self.emitCodeBlock(&code_lines, code_block_lang, max_width, &segments, allocator);
        }

        if (table_lines.items.len > 0) {
            try self.emitTable(&table_lines, max_width, &segments, allocator);
        }

        return segments.toOwnedSlice(allocator);
    }

    fn emitCodeBlock(
        self: Markdown,
        code_lines: *std.ArrayList(u8),
        lang: ?[]const u8,
        max_width: usize,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        const code = try code_lines.toOwnedSlice(allocator);
        defer allocator.free(code);
        var code_block = CodeBlock.init(code).withTheme(self.theme);
        if (lang) |l| {
            code_block = code_block.withLanguage(l);
        }
        const code_segments = try code_block.render(max_width, allocator);
        defer allocator.free(code_segments);
        try segments.appendSlice(allocator, code_segments);
    }

    fn isTableRow(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) return false;
        return std.mem.indexOfScalar(u8, trimmed, '|') != null;
    }

    fn isTableSeparator(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t|");
        if (trimmed.len == 0) return false;

        var dash_count: usize = 0;
        for (trimmed) |c| {
            switch (c) {
                '-' => dash_count += 1,
                ':', '|', ' ' => {},
                else => return false,
            }
        }
        return dash_count >= 3;
    }

    fn parseTableAlignment(sep_cell: []const u8) JustifyMethod {
        const trimmed = std.mem.trim(u8, sep_cell, " \t");
        if (trimmed.len == 0) return .left;

        const starts_colon = trimmed[0] == ':';
        const ends_colon = trimmed[trimmed.len - 1] == ':';

        if (starts_colon and ends_colon) return .center;
        if (ends_colon) return .right;
        return .left;
    }

    fn splitTableCells(line: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
        var result: std.ArrayList([]const u8) = .empty;

        const content = std.mem.trim(u8, std.mem.trim(u8, line, " \t"), "|");

        var iter = std.mem.splitScalar(u8, content, '|');
        while (iter.next()) |cell| {
            try result.append(allocator, std.mem.trim(u8, cell, " \t"));
        }

        return result.toOwnedSlice(allocator);
    }

    fn emitTable(
        self: Markdown,
        table_lines: *std.ArrayList([]const u8),
        max_width: usize,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        defer table_lines.clearRetainingCapacity();

        const is_valid_table = table_lines.items.len >= 2 and isTableSeparator(table_lines.items[1]);

        if (!is_valid_table) {
            for (table_lines.items) |line| {
                try self.renderInlineText(line, null, segments, allocator);
                try segments.append(allocator, Segment.line());
            }
            return;
        }

        const header_cells = try splitTableCells(table_lines.items[0], allocator);
        defer allocator.free(header_cells);

        const sep_cells = try splitTableCells(table_lines.items[1], allocator);
        defer allocator.free(sep_cells);

        var table = Table.init(allocator);
        defer table.deinit();

        for (header_cells, 0..) |header, i| {
            const justify = if (i < sep_cells.len) parseTableAlignment(sep_cells[i]) else .left;
            _ = table.withColumn(Column.init(header).withJustify(justify));
        }

        _ = table.withHeaderStyle(self.theme.table_header_style);
        _ = table.withBorderStyle(self.theme.table_border_style);
        _ = table.withBoxStyle(self.theme.table_box_style);

        for (table_lines.items[2..]) |row_line| {
            const row_cells = try splitTableCells(row_line, allocator);
            defer allocator.free(row_cells);

            const row = try allocator.alloc([]const u8, header_cells.len);
            defer allocator.free(row);

            for (0..header_cells.len) |i| {
                row[i] = if (i < row_cells.len) row_cells[i] else "";
            }

            try table.addRow(row);
        }

        const table_segments = try table.render(max_width, allocator);
        defer allocator.free(table_segments);
        try segments.appendSlice(allocator, table_segments);
    }

    fn parseFenceOpen(line: []const u8) ?[]const u8 {
        if (line.len < 3) return null;
        if (!std.mem.startsWith(u8, line, "```")) return null;

        const rest = std.mem.trimStart(u8, line[3..], " \t");
        if (rest.len == 0) return "";

        const lang_end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        return rest[0..lang_end];
    }

    fn parseFenceClose(line: []const u8) bool {
        if (line.len < 3) return false;
        const trimmed = std.mem.trimEnd(u8, line, " \t");
        return std.mem.eql(u8, trimmed, "```");
    }

    const HeaderInfo = struct {
        level: HeaderLevel,
        text: []const u8,
    };

    const OrderedListItem = struct {
        number: usize,
        text: []const u8,
        indent_level: usize,
    };

    const TaskCheckbox = enum {
        unchecked,
        checked,
    };

    const UnorderedListItem = struct {
        text: []const u8,
        indent_level: usize,
        checkbox: ?TaskCheckbox = null,
    };

    const BlockquoteItem = struct {
        text: []const u8,
        depth: usize,
    };

    fn countLeadingSpaces(line: []const u8) usize {
        var count: usize = 0;
        while (count < line.len and line[count] == ' ') : (count += 1) {}
        return count;
    }

    fn parseOrderedListItem(line: []const u8) ?OrderedListItem {
        const indent = countLeadingSpaces(line);
        const rest = line[indent..];
        if (rest.len == 0) return null;

        var num_end: usize = 0;
        while (num_end < rest.len and std.ascii.isDigit(rest[num_end])) : (num_end += 1) {}

        if (num_end == 0 or num_end >= rest.len) return null;

        const delimiter = rest[num_end];
        if (delimiter != '.' and delimiter != ')') return null;

        const after_delim = num_end + 1;
        if (after_delim >= rest.len or rest[after_delim] != ' ') return null;

        const number = std.fmt.parseInt(usize, rest[0..num_end], 10) catch return null;

        return .{
            .number = number,
            .text = std.mem.trim(u8, rest[after_delim..], " \t"),
            .indent_level = indent / 2,
        };
    }

    fn parseUnorderedListItem(line: []const u8) ?UnorderedListItem {
        const indent = countLeadingSpaces(line);
        const rest = line[indent..];
        if (rest.len < 2) return null;

        const bullet = rest[0];
        if (bullet != '-' and bullet != '*' and bullet != '+') return null;
        if (rest[1] != ' ') return null;

        const after_bullet = rest[2..];

        if (after_bullet.len >= 3 and after_bullet[0] == '[' and after_bullet[2] == ']') {
            const checkbox_char = after_bullet[1];
            const checkbox: ?TaskCheckbox = if (checkbox_char == ' ')
                .unchecked
            else if (checkbox_char == 'x' or checkbox_char == 'X')
                .checked
            else
                null;

            if (checkbox) |cb| {
                const text_start: usize = if (after_bullet.len > 3 and after_bullet[3] == ' ') 4 else 3;
                return .{
                    .text = std.mem.trim(u8, after_bullet[text_start..], " \t"),
                    .indent_level = indent / 2,
                    .checkbox = cb,
                };
            }
        }

        return .{
            .text = std.mem.trim(u8, after_bullet, " \t"),
            .indent_level = indent / 2,
        };
    }

    fn parseBlockquote(line: []const u8) ?BlockquoteItem {
        var pos: usize = 0;
        var depth: usize = 0;

        while (pos < line.len) {
            while (pos < line.len and line[pos] == ' ') : (pos += 1) {}
            if (pos >= line.len or line[pos] != '>') break;

            depth += 1;
            pos += 1;

            if (pos < line.len and line[pos] == ' ') pos += 1;
        }

        if (depth == 0) return null;

        return .{
            .text = line[pos..],
            .depth = depth,
        };
    }

    fn renderListIndent(
        self: Markdown,
        indent_level: usize,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        const base_indent = indent_level * self.theme.list_indent;
        if (base_indent > 0) {
            const indent_str = try allocator.alloc(u8, base_indent);
            @memset(indent_str, ' ');
            try segments.append(allocator, Segment.plain(indent_str));
        }
    }

    fn renderUnorderedListItem(
        self: Markdown,
        item: UnorderedListItem,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        try self.renderListIndent(item.indent_level, segments, allocator);

        const marker_char, const marker_style = if (item.checkbox) |checkbox| switch (checkbox) {
            .unchecked => .{ self.theme.task_unchecked_char, self.theme.task_unchecked_style },
            .checked => .{ self.theme.task_checked_char, self.theme.task_checked_style },
        } else .{ self.theme.list_bullet_char, self.theme.list_bullet_style };

        const marker_with_space = try std.fmt.allocPrint(allocator, "{s} ", .{marker_char});
        try segments.append(allocator, Segment.styled(marker_with_space, marker_style));

        try self.renderInlineText(item.text, null, segments, allocator);
    }

    fn renderOrderedListItem(
        self: Markdown,
        item: OrderedListItem,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        try self.renderListIndent(item.indent_level, segments, allocator);

        const number_str = try std.fmt.allocPrint(allocator, "{d}. ", .{item.number});
        try segments.append(allocator, Segment.styled(number_str, self.theme.list_number_style));

        try self.renderInlineText(item.text, null, segments, allocator);
    }

    fn renderBlockquoteLine(
        self: Markdown,
        item: BlockquoteItem,
        segments: *std.ArrayList(Segment),
        allocator: std.mem.Allocator,
    ) !void {
        for (0..item.depth) |_| {
            const border_with_space = try std.fmt.allocPrint(allocator, "{s} ", .{self.theme.blockquote_border_char});
            try segments.append(allocator, Segment.styled(border_with_space, self.theme.blockquote_border_style));

            if (self.theme.blockquote_indent > 0) {
                const indent_str = try allocator.alloc(u8, self.theme.blockquote_indent);
                @memset(indent_str, ' ');
                try segments.append(allocator, Segment.plain(indent_str));
            }
        }

        if (item.text.len > 0) {
            try self.renderInlineText(item.text, self.theme.blockquote_style, segments, allocator);
        }
    }

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

    fn parseHorizontalRule(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len < 3) return false;

        const rule_char = trimmed[0];
        if (rule_char != '-' and rule_char != '*' and rule_char != '_') return false;

        var char_count: usize = 0;
        for (trimmed) |c| {
            if (c == rule_char) {
                char_count += 1;
            } else if (c != ' ') {
                return false;
            }
        }

        return char_count >= 3;
    }

    const InlineSpan = struct {
        text: []const u8,
        style_type: StyleType,
        link_url: ?[]const u8 = null,
        image_url: ?[]const u8 = null,

        const StyleType = enum {
            plain,
            bold,
            italic,
            bold_italic,
            strikethrough,
            link,
            code,
            image,
        };
    };

    fn parseInlineStyles(text: []const u8, allocator: std.mem.Allocator) ![]InlineSpan {
        var spans: std.ArrayList(InlineSpan) = .empty;
        var pos: usize = 0;

        while (pos < text.len) {
            if (tryParseImage(text, pos)) |result| {
                try spans.append(allocator, .{
                    .text = result.text,
                    .style_type = .image,
                    .image_url = result.url,
                });
                pos = result.end_pos;
                continue;
            }

            if (tryParseLink(text, pos)) |result| {
                try spans.append(allocator, .{
                    .text = result.text,
                    .style_type = .link,
                    .link_url = result.url,
                });
                pos = result.end_pos;
                continue;
            }

            if (tryParseInlineCode(text, pos)) |result| {
                try spans.append(allocator, .{
                    .text = result.content,
                    .style_type = .code,
                });
                pos = result.end_pos;
                continue;
            }

            if (tryParseStrikethrough(text, pos)) |result| {
                try spans.append(allocator, .{
                    .text = result.content,
                    .style_type = .strikethrough,
                });
                pos = result.end_pos;
                continue;
            }

            if (tryParseStyledSpan(text, pos)) |result| {
                try spans.append(allocator, .{
                    .text = result.content,
                    .style_type = result.style_type,
                });
                pos = result.end_pos;
                continue;
            }

            const plain_start = pos;
            pos = advanceToNextDelimiter(text, pos);

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

    const LinkResult = struct {
        text: []const u8,
        url: []const u8,
        end_pos: usize,
    };

    fn tryParseImage(text: []const u8, pos: usize) ?LinkResult {
        if (pos >= text.len or text[pos] != '!') return null;
        return tryParseLink(text, pos + 1);
    }

    fn findMatchingDelimiter(text: []const u8, start: usize, open: u8, close: u8) ?usize {
        var depth: usize = 1;
        var pos: usize = start;

        while (pos < text.len and depth > 0) {
            if (text[pos] == open) {
                depth += 1;
            } else if (text[pos] == close) {
                depth -= 1;
            }
            if (depth > 0) pos += 1;
        }

        return if (depth == 0) pos else null;
    }

    fn tryParseLink(text: []const u8, pos: usize) ?LinkResult {
        if (pos >= text.len or text[pos] != '[') return null;

        const text_start = pos + 1;
        const text_end = findMatchingDelimiter(text, text_start, '[', ']') orelse return null;

        const paren_start = text_end + 1;
        if (paren_start >= text.len or text[paren_start] != '(') return null;

        const url_start = paren_start + 1;
        const url_end = findMatchingDelimiter(text, url_start, '(', ')') orelse return null;

        return .{
            .text = text[text_start..text_end],
            .url = text[url_start..url_end],
            .end_pos = url_end + 1,
        };
    }

    const ParseResult = struct {
        content: []const u8,
        style_type: InlineSpan.StyleType,
        end_pos: usize,
    };

    fn tryParseStyledSpan(text: []const u8, pos: usize) ?ParseResult {
        const c = text[pos];
        if (c != '*' and c != '_') return null;

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

    const InlineCodeResult = struct {
        content: []const u8,
        end_pos: usize,
    };

    fn tryParseInlineCode(text: []const u8, pos: usize) ?InlineCodeResult {
        if (pos >= text.len or text[pos] != '`') return null;

        var backtick_count: usize = 0;
        var p = pos;
        while (p < text.len and text[p] == '`') : (p += 1) {
            backtick_count += 1;
        }
        if (backtick_count > 2) return null;

        const content_start = pos + backtick_count;
        if (content_start >= text.len) return null;

        var search_pos = content_start;
        while (search_pos + backtick_count <= text.len) : (search_pos += 1) {
            if (!isRepeatedChar(text[search_pos..][0..backtick_count], '`')) continue;

            const after_pos = search_pos + backtick_count;
            if (after_pos < text.len and text[after_pos] == '`') continue;

            return .{
                .content = text[content_start..search_pos],
                .end_pos = after_pos,
            };
        }

        return null;
    }

    fn tryParseStrikethrough(text: []const u8, pos: usize) ?InlineCodeResult {
        if (pos + 2 > text.len) return null;
        if (text[pos] != '~' or text[pos + 1] != '~') return null;

        const content_start = pos + 2;
        if (findClosingDelimiter(text, content_start, '~', 2)) |end| {
            return .{
                .content = text[content_start..end],
                .end_pos = end + 2,
            };
        }
        return null;
    }

    fn advanceToNextDelimiter(text: []const u8, start: usize) usize {
        var pos = start;
        while (pos < text.len and text[pos] != '*' and text[pos] != '_' and text[pos] != '[' and text[pos] != '`' and text[pos] != '!' and text[pos] != '~') {
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
            if (span.style_type == .image) {
                const final_style: Style = if (base_style) |bs|
                    bs.combine(self.theme.image_style)
                else
                    self.theme.image_style;

                try segments.append(allocator, Segment.styled(self.theme.image_prefix, final_style));
                if (span.text.len > 0) {
                    try segments.append(allocator, Segment.styled(span.text, final_style));
                } else {
                    if (span.image_url) |url| {
                        try segments.append(allocator, Segment.styled(url, final_style));
                    }
                }
                try segments.append(allocator, Segment.styled(self.theme.image_suffix, final_style));
                continue;
            }

            const inline_style: ?Style = switch (span.style_type) {
                .plain => null,
                .bold => self.theme.bold_style,
                .italic => self.theme.italic_style,
                .bold_italic => self.theme.bold_italic_style,
                .strikethrough => self.theme.strikethrough_style,
                .code => self.theme.inline_code_style,
                .link => blk: {
                    var link_style = self.theme.link_style;
                    if (span.link_url) |url| {
                        link_style = link_style.hyperlink(url);
                    }
                    break :blk link_style;
                },
                .image => unreachable, // Handled above
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

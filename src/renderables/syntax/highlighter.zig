const std = @import("std");
const Segment = @import("../../segment.zig").Segment;
const Style = @import("../../style.zig").Style;
const Color = @import("../../color.zig").Color;
const cells = @import("../../cells.zig");

const Language = @import("language.zig").Language;
const SyntaxTheme = @import("theme.zig").SyntaxTheme;
const tokenizer = @import("tokenizer.zig");
const zig_keywords = tokenizer.zig_keywords;
const zig_builtins = tokenizer.zig_builtins;
const zig_types = tokenizer.zig_types;

pub const Syntax = struct {
    code: []const u8,
    language: Language = .plain,
    theme: SyntaxTheme = SyntaxTheme.default,
    show_line_numbers: bool = false,
    start_line: usize = 1,
    word_wrap: bool = false,
    tab_size: u8 = 4,
    indent_guides: bool = false,
    indent_guide_char: []const u8 = "|",
    highlight_lines: ?[]const usize = null,
    allocator: std.mem.Allocator,
    owns_code: bool = false,

    pub fn init(allocator: std.mem.Allocator, code: []const u8) Syntax {
        return .{
            .code = code,
            .allocator = allocator,
        };
    }

    pub fn renderDuped(self: Syntax, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        const segments = try self.render(max_width, allocator);

        for (segments) |*seg| {
            if (seg.text.len > 0 and !std.mem.eql(u8, seg.text, "\n")) {
                seg.text = try allocator.dupe(u8, seg.text);
            }
        }

        return segments;
    }

    pub fn withLanguage(self: Syntax, lang: Language) Syntax {
        var s = self;
        s.language = lang;
        return s;
    }

    /// Auto-detect language from filename and/or content
    pub fn withAutoDetect(self: Syntax, filename: ?[]const u8) Syntax {
        var s = self;
        s.language = Language.detect(filename, s.code);
        return s;
    }

    /// Create syntax highlighter from code string with filename for language detection
    pub fn fromFile(allocator: std.mem.Allocator, code: []const u8, filename: []const u8) Syntax {
        return Syntax{
            .code = code,
            .language = Language.detect(filename, code),
            .allocator = allocator,
        };
    }

    /// Load code from filesystem and create syntax highlighter (auto-detects language)
    pub fn loadFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Syntax {
        const file = try std.Io.Dir.openFile(.cwd(), io, path, .{});
        defer file.close(io);

        var read_buf: [4096]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);
        const code = try file_reader.interface.allocRemaining(allocator, .unlimited);

        return Syntax{
            .code = code,
            .language = Language.detect(path, code),
            .allocator = allocator,
            .owns_code = true,
        };
    }

    /// Free memory allocated by loadFile. Only call on Syntax instances created via loadFile.
    pub fn deinit(self: *Syntax) void {
        if (self.owns_code) {
            self.allocator.free(self.code);
        }
    }

    pub fn withTheme(self: Syntax, theme: SyntaxTheme) Syntax {
        var s = self;
        s.theme = theme;
        return s;
    }

    pub fn withLineNumbers(self: Syntax) Syntax {
        var s = self;
        s.show_line_numbers = true;
        return s;
    }

    pub fn withStartLine(self: Syntax, line: usize) Syntax {
        var s = self;
        s.start_line = line;
        return s;
    }

    pub fn withWordWrap(self: Syntax) Syntax {
        var s = self;
        s.word_wrap = true;
        return s;
    }

    pub fn withTabSize(self: Syntax, size: u8) Syntax {
        var s = self;
        s.tab_size = size;
        return s;
    }

    pub fn withIndentGuides(self: Syntax) Syntax {
        var s = self;
        s.indent_guides = true;
        return s;
    }

    pub fn withIndentGuideChar(self: Syntax, char: []const u8) Syntax {
        var s = self;
        s.indent_guide_char = char;
        return s;
    }

    /// Highlight specific line numbers (e.g., for showing error locations).
    /// Line numbers are 1-based (matching start_line convention).
    pub fn withHighlightLines(self: Syntax, lines: []const usize) Syntax {
        var s = self;
        s.highlight_lines = lines;
        return s;
    }

    /// Check if a given line number should be highlighted.
    fn isLineHighlighted(self: Syntax, line_num: usize) bool {
        if (self.highlight_lines) |lines| {
            for (lines) |hl| {
                if (hl == line_num) return true;
            }
        }
        return false;
    }

    pub fn render(self: Syntax, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        var lines = std.mem.splitScalar(u8, self.code, '\n');
        var line_num: usize = self.start_line;

        // Calculate available width for code (accounting for line numbers)
        const line_num_width: usize = if (self.show_line_numbers) 5 else 0; // "NNNN "
        const code_width: usize = if (max_width > line_num_width) max_width - line_num_width else max_width;

        while (lines.next()) |line| {
            const is_highlighted = self.isLineHighlighted(line_num);

            if (self.show_line_numbers) {
                var buf: [16]u8 = undefined;
                const line_str = std.fmt.bufPrint(&buf, "{d:>4} ", .{line_num}) catch "???? ";
                const line_str_copy = try allocator.dupe(u8, line_str);
                const line_num_style = if (is_highlighted)
                    self.theme.highlight_line_number_style
                else
                    self.theme.line_number_style;
                try segments.append(allocator, Segment.styled(line_str_copy, self.theme.applyBackground(line_num_style)));
            }

            if (self.word_wrap and code_width > 0) {
                var line_segments: std.ArrayList(Segment) = .empty;
                try self.highlightLine(&line_segments, allocator, line, is_highlighted);
                const highlighted = try line_segments.toOwnedSlice(allocator);
                defer allocator.free(highlighted);

                const wrapped = try wrapSegments(highlighted, code_width, allocator);
                defer allocator.free(wrapped);

                var after_wrap_newline = false;
                for (wrapped) |seg| {
                    const is_newline = std.mem.eql(u8, seg.text, "\n");
                    if (after_wrap_newline and self.show_line_numbers and !is_newline) {
                        const indent = try allocator.dupe(u8, "     ");
                        const indent_style = if (is_highlighted)
                            self.theme.highlight_line_number_style
                        else
                            self.theme.line_number_style;
                        try segments.append(allocator, Segment.styled(indent, self.theme.applyBackground(indent_style)));
                    }
                    try segments.append(allocator, Segment.styledOptional(seg.text, self.theme.applyBackgroundOpt(seg.style)));
                    after_wrap_newline = is_newline;
                }
            } else {
                try self.highlightLine(&segments, allocator, line, is_highlighted);
            }

            try segments.append(allocator, Segment.line());
            line_num += 1;
        }

        return segments.toOwnedSlice(allocator);
    }

    fn highlightLine(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8, is_highlighted: bool) !void {
        const expanded = try self.expandTabs(line, allocator);

        if (self.indent_guides) {
            try self.renderWithIndentGuides(segments, allocator, expanded, is_highlighted);
        } else {
            try self.highlightContent(segments, allocator, expanded, is_highlighted);
        }
    }

    /// Apply syntax highlighting to content based on language.
    fn highlightContent(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, content: []const u8, is_highlighted: bool) !void {
        switch (self.language) {
            .zig => try self.highlightZig(segments, allocator, content, is_highlighted),
            .json => try self.highlightJson(segments, allocator, content, is_highlighted),
            .markdown => try self.highlightMarkdown(segments, allocator, content, is_highlighted),
            .python,
            .javascript,
            .typescript,
            .rust,
            .go,
            .c,
            .cpp,
            .bash,
            .yaml,
            .toml,
            .xml,
            .html,
            .css,
            .sql,
            .plain,
            => try segments.append(allocator, self.defaultSegmentHighlighted(content, is_highlighted)),
        }
    }

    /// Render a line with indent guides at each tab stop in the leading whitespace.
    fn renderWithIndentGuides(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8, is_highlighted: bool) !void {
        var indent_end: usize = 0;
        while (indent_end < line.len and line[indent_end] == ' ') : (indent_end += 1) {}

        if (indent_end > 0) {
            const tab_size: usize = @intCast(self.tab_size);
            var col: usize = 0;

            while (col < indent_end) {
                const next_tab_stop = ((col / tab_size) + 1) * tab_size;

                if (next_tab_stop <= indent_end and indent_end - col >= tab_size) {
                    try segments.append(allocator, self.styledSegmentHighlighted(
                        self.indent_guide_char,
                        self.theme.indent_guide_style,
                        is_highlighted,
                    ));
                    const spaces_after_guide = tab_size - self.indent_guide_char.len;
                    if (spaces_after_guide > 0) {
                        const space_fill = try allocator.alloc(u8, spaces_after_guide);
                        @memset(space_fill, ' ');
                        try segments.append(allocator, self.defaultSegmentHighlighted(space_fill, is_highlighted));
                    }
                    col = next_tab_stop;
                } else {
                    const spaces_to_end = indent_end - col;
                    const space_fill = try allocator.alloc(u8, spaces_to_end);
                    @memset(space_fill, ' ');
                    try segments.append(allocator, self.defaultSegmentHighlighted(space_fill, is_highlighted));
                    col = indent_end;
                }
            }
        }

        const content = line[indent_end..];
        if (content.len > 0) {
            try self.highlightContent(segments, allocator, content, is_highlighted);
        }
    }

    /// Expand tabs to spaces based on tab_size setting.
    /// Returns the original slice if no tabs are present (no allocation).
    fn expandTabs(self: Syntax, line: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const tab_count = std.mem.count(u8, line, "\t");
        if (tab_count == 0) return line;

        // Over-allocate: actual size may be smaller due to tab-stop alignment
        const max_len = line.len - tab_count + tab_count * self.tab_size;
        const result = try allocator.alloc(u8, max_len);

        var src_pos: usize = 0;
        var dst_pos: usize = 0;
        var column: usize = 0;

        while (src_pos < line.len) : (src_pos += 1) {
            if (line[src_pos] == '\t') {
                // Calculate spaces to next tab stop
                const spaces_to_tab_stop = self.tab_size - @as(u8, @intCast(column % self.tab_size));
                @memset(result[dst_pos..][0..spaces_to_tab_stop], ' ');
                dst_pos += spaces_to_tab_stop;
                column += spaces_to_tab_stop;
            } else {
                result[dst_pos] = line[src_pos];
                dst_pos += 1;
                column += 1;
            }
        }

        return result[0..dst_pos];
    }

    fn defaultSegmentHighlighted(self: Syntax, text: []const u8, is_highlighted: bool) Segment {
        if (is_highlighted) {
            const style = if (self.theme.default_style.isEmpty())
                self.theme.highlight_line_style
            else
                self.applyHighlightBackground(self.theme.default_style);
            return Segment.styled(text, style);
        }
        const base_style = if (self.theme.default_style.isEmpty()) null else self.theme.default_style;
        return Segment.styledOptional(text, self.theme.applyBackgroundOpt(base_style));
    }

    fn styledSegmentHighlighted(self: Syntax, text: []const u8, style: Style, is_highlighted: bool) Segment {
        if (is_highlighted) {
            return Segment.styled(text, self.applyHighlightBackground(style));
        }
        return Segment.styled(text, self.theme.applyBackground(style));
    }

    /// Apply highlight line background to a style (overrides any existing background).
    fn applyHighlightBackground(self: Syntax, style: Style) Style {
        var result = style;
        result.bgcolor = self.theme.highlight_line_style.bgcolor;
        return result;
    }

    fn highlightZig(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8, is_highlighted: bool) !void {
        var i: usize = 0;

        while (i < line.len) {
            if (std.mem.startsWith(u8, line[i..], "//")) {
                try segments.append(allocator, self.styledSegmentHighlighted(line[i..], self.theme.comment_style, is_highlighted));
                return;
            }

            if (line[i] == '"') {
                const end = self.findStringEnd(line, i);
                try segments.append(allocator, self.styledSegmentHighlighted(line[i..end], self.theme.string_style, is_highlighted));
                i = end;
                continue;
            }

            if (line[i] == '\'') {
                const end = self.findCharEnd(line, i);
                try segments.append(allocator, self.styledSegmentHighlighted(line[i..end], self.theme.string_style, is_highlighted));
                i = end;
                continue;
            }

            if (line[i] == '@') {
                const end = self.findIdentEnd(line, i + 1);
                const builtin = line[i..end];
                if (zig_builtins.has(builtin)) {
                    try segments.append(allocator, self.styledSegmentHighlighted(builtin, self.theme.builtin_style, is_highlighted));
                } else {
                    try segments.append(allocator, self.defaultSegmentHighlighted(builtin, is_highlighted));
                }
                i = end;
                continue;
            }

            if (std.ascii.isDigit(line[i]) or (line[i] == '.' and i + 1 < line.len and std.ascii.isDigit(line[i + 1]))) {
                const end = self.findNumberEnd(line, i);
                try segments.append(allocator, self.styledSegmentHighlighted(line[i..end], self.theme.number_style, is_highlighted));
                i = end;
                continue;
            }

            if (std.ascii.isAlphabetic(line[i]) or line[i] == '_') {
                const end = self.findIdentEnd(line, i);
                const ident = line[i..end];

                if (zig_keywords.has(ident)) {
                    try segments.append(allocator, self.styledSegmentHighlighted(ident, self.theme.keyword_style, is_highlighted));
                } else if (zig_types.has(ident)) {
                    try segments.append(allocator, self.styledSegmentHighlighted(ident, self.theme.type_style, is_highlighted));
                } else if (end < line.len and line[end] == '(') {
                    try segments.append(allocator, self.styledSegmentHighlighted(ident, self.theme.function_style, is_highlighted));
                } else {
                    try segments.append(allocator, self.defaultSegmentHighlighted(ident, is_highlighted));
                }
                i = end;
                continue;
            }

            if (self.isOperator(line[i])) {
                try segments.append(allocator, self.styledSegmentHighlighted(line[i .. i + 1], self.theme.operator_style, is_highlighted));
                i += 1;
                continue;
            }

            if (self.isPunctuation(line[i])) {
                try segments.append(allocator, self.styledSegmentHighlighted(line[i .. i + 1], self.theme.punctuation_style, is_highlighted));
                i += 1;
                continue;
            }

            try segments.append(allocator, self.defaultSegmentHighlighted(line[i .. i + 1], is_highlighted));
            i += 1;
        }
    }

    fn highlightJson(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8, is_highlighted: bool) !void {
        var i: usize = 0;

        while (i < line.len) {
            if (line[i] == '"') {
                const end = self.findStringEnd(line, i);
                const str_content = line[i..end];
                if (end < line.len and line[end] == ':') {
                    try segments.append(allocator, self.styledSegmentHighlighted(str_content, self.theme.keyword_style, is_highlighted));
                } else {
                    try segments.append(allocator, self.styledSegmentHighlighted(str_content, self.theme.string_style, is_highlighted));
                }
                i = end;
                continue;
            }

            const keyword: ?[]const u8 = if (std.mem.startsWith(u8, line[i..], "true"))
                "true"
            else if (std.mem.startsWith(u8, line[i..], "false"))
                "false"
            else if (std.mem.startsWith(u8, line[i..], "null"))
                "null"
            else
                null;

            if (keyword) |kw| {
                try segments.append(allocator, self.styledSegmentHighlighted(kw, self.theme.keyword_style, is_highlighted));
                i += kw.len;
                continue;
            }

            if (std.ascii.isDigit(line[i]) or (line[i] == '-' and i + 1 < line.len and std.ascii.isDigit(line[i + 1]))) {
                const end = self.findNumberEnd(line, i);
                try segments.append(allocator, self.styledSegmentHighlighted(line[i..end], self.theme.number_style, is_highlighted));
                i = end;
                continue;
            }

            if (self.isPunctuation(line[i])) {
                try segments.append(allocator, self.styledSegmentHighlighted(line[i .. i + 1], self.theme.punctuation_style, is_highlighted));
                i += 1;
                continue;
            }

            try segments.append(allocator, self.defaultSegmentHighlighted(line[i .. i + 1], is_highlighted));
            i += 1;
        }
    }

    fn highlightMarkdown(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8, is_highlighted: bool) !void {
        if (line.len == 0) return;

        if (std.mem.startsWith(u8, line, "#")) {
            try segments.append(allocator, self.styledSegmentHighlighted(line, self.theme.keyword_style.bold(), is_highlighted));
            return;
        }

        if (std.mem.startsWith(u8, line, "```")) {
            try segments.append(allocator, self.styledSegmentHighlighted(line, self.theme.comment_style, is_highlighted));
            return;
        }

        if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ") or std.mem.startsWith(u8, line, "+ ")) {
            try segments.append(allocator, self.styledSegmentHighlighted(line[0..2], self.theme.keyword_style, is_highlighted));
            try segments.append(allocator, self.defaultSegmentHighlighted(line[2..], is_highlighted));
            return;
        }

        if (std.mem.startsWith(u8, line, "> ")) {
            try segments.append(allocator, self.styledSegmentHighlighted(line, self.theme.comment_style.italic(), is_highlighted));
            return;
        }

        var i: usize = 0;
        while (i < line.len) {
            if (line[i] == '`') {
                var end = i + 1;
                while (end < line.len and line[end] != '`') : (end += 1) {}
                if (end < line.len) {
                    try segments.append(allocator, self.styledSegmentHighlighted(line[i .. end + 1], self.theme.string_style, is_highlighted));
                    i = end + 1;
                    continue;
                }
            }

            if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '*') {
                var end = i + 2;
                while (end + 1 < line.len and !(line[end] == '*' and line[end + 1] == '*')) : (end += 1) {}
                if (end + 1 < line.len) {
                    try segments.append(allocator, self.styledSegmentHighlighted(line[i .. end + 2], self.theme.keyword_style.bold(), is_highlighted));
                    i = end + 2;
                    continue;
                }
            }

            if (line[i] == '*' or line[i] == '_') {
                const marker = line[i];
                var end = i + 1;
                while (end < line.len and line[end] != marker) : (end += 1) {}
                if (end < line.len) {
                    try segments.append(allocator, self.styledSegmentHighlighted(line[i .. end + 1], self.theme.default_style.italic(), is_highlighted));
                    i = end + 1;
                    continue;
                }
            }

            if (line[i] == '[') {
                var bracket_end = i + 1;
                while (bracket_end < line.len and line[bracket_end] != ']') : (bracket_end += 1) {}
                if (bracket_end < line.len and bracket_end + 1 < line.len and line[bracket_end + 1] == '(') {
                    var paren_end = bracket_end + 2;
                    while (paren_end < line.len and line[paren_end] != ')') : (paren_end += 1) {}
                    if (paren_end < line.len) {
                        try segments.append(allocator, self.styledSegmentHighlighted(line[i .. paren_end + 1], self.theme.builtin_style, is_highlighted));
                        i = paren_end + 1;
                        continue;
                    }
                }
            }

            try segments.append(allocator, self.defaultSegmentHighlighted(line[i .. i + 1], is_highlighted));
            i += 1;
        }
    }

    fn findStringEnd(_: Syntax, line: []const u8, start: usize) usize {
        var i = start + 1;
        while (i < line.len) : (i += 1) {
            if (line[i] == '\\' and i + 1 < line.len) {
                i += 1;
                continue;
            }
            if (line[i] == '"') {
                return i + 1;
            }
        }
        return line.len;
    }

    fn findCharEnd(_: Syntax, line: []const u8, start: usize) usize {
        var i = start + 1;
        while (i < line.len) : (i += 1) {
            if (line[i] == '\\' and i + 1 < line.len) {
                i += 1;
                continue;
            }
            if (line[i] == '\'') {
                return i + 1;
            }
        }
        return line.len;
    }

    fn findIdentEnd(_: Syntax, line: []const u8, start: usize) usize {
        var i = start;
        while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) : (i += 1) {}
        return i;
    }

    fn findNumberEnd(_: Syntax, line: []const u8, start: usize) usize {
        var i = start;
        if (i < line.len and line[i] == '-') i += 1;
        if (i + 1 < line.len and line[i] == '0' and (line[i + 1] == 'x' or line[i + 1] == 'b' or line[i + 1] == 'o')) {
            i += 2;
            while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) : (i += 1) {}
        } else {
            while (i < line.len and (std.ascii.isDigit(line[i]) or line[i] == '.' or line[i] == '_' or line[i] == 'e' or line[i] == 'E' or line[i] == '-' or line[i] == '+')) : (i += 1) {}
        }
        return i;
    }

    fn isOperator(_: Syntax, c: u8) bool {
        return switch (c) {
            '+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~' => true,
            else => false,
        };
    }

    fn isPunctuation(_: Syntax, c: u8) bool {
        return switch (c) {
            '{', '}', '[', ']', '(', ')', ',', '.', ':', ';' => true,
            else => false,
        };
    }

    /// Wrap styled segments to fit within max_width, preserving styles across wrapped lines.
    /// Prefers breaking at word boundaries (spaces) when possible, falls back to character-level
    /// wrapping for long words that exceed the available width.
    fn wrapSegments(line_segments: []const Segment, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        if (max_width == 0) {
            return allocator.dupe(Segment, line_segments);
        }

        var result: std.ArrayList(Segment) = .empty;
        var current_width: usize = 0;

        // Track position of last space for word-boundary breaking
        var last_space_result_idx: ?usize = null;

        for (line_segments) |seg| {
            const seg_width = seg.cellLength();

            // If segment fits on current line, append it
            if (current_width + seg_width <= max_width) {
                // Check if this segment contains a space (potential break point)
                if (std.mem.lastIndexOfScalar(u8, seg.text, ' ')) |_| {
                    last_space_result_idx = result.items.len;
                }
                try result.append(allocator, seg);
                current_width += seg_width;
                continue;
            }

            // Segment doesn't fit - need to wrap within it
            var remaining_text = seg.text;

            while (remaining_text.len > 0) {
                if (current_width >= max_width) {
                    try result.append(allocator, Segment.line());
                    current_width = 0;
                    last_space_result_idx = null;
                }

                const remaining_width = cells.cellLen(remaining_text);
                const available = max_width - current_width;

                if (remaining_width <= available) {
                    // Check for space in this final piece
                    if (std.mem.lastIndexOfScalar(u8, remaining_text, ' ')) |_| {
                        last_space_result_idx = result.items.len;
                    }
                    try result.append(allocator, Segment.styledOptional(remaining_text, seg.style));
                    current_width += remaining_width;
                    break;
                }

                // Find word boundary within available space
                const byte_limit = cells.cellToByteIndex(remaining_text, available);
                var break_byte = byte_limit;
                var break_width = available;

                // Look for last space within the available width
                if (std.mem.lastIndexOfScalar(u8, remaining_text[0..byte_limit], ' ')) |space_pos| {
                    // Found a space - break after it
                    break_byte = space_pos + 1;
                    break_width = cells.cellLen(remaining_text[0..break_byte]);
                } else if (current_width > 0 and last_space_result_idx != null) {
                    // No space in current chunk, but we have a previous space on this line
                    // Rewind to the last space by inserting a newline after it
                    const space_idx = last_space_result_idx.?;
                    const space_seg = result.items[space_idx];

                    // Find the last space in that segment and split it
                    if (std.mem.lastIndexOfScalar(u8, space_seg.text, ' ')) |sp| {
                        // Split at the space: keep text up to and including space,
                        // then insert newline, then continue with rest
                        const before_space = space_seg.text[0 .. sp + 1];
                        const after_space = space_seg.text[sp + 1 ..];

                        // Update the segment to end at space
                        result.items[space_idx] = Segment.styledOptional(before_space, space_seg.style);

                        // Collect segments after the space to re-process
                        var to_reprocess: std.ArrayList(Segment) = .empty;
                        defer to_reprocess.deinit(allocator);

                        if (after_space.len > 0) {
                            try to_reprocess.append(allocator, Segment.styledOptional(after_space, space_seg.style));
                        }

                        // Add remaining segments from result after space_idx
                        for (result.items[space_idx + 1 ..]) |s| {
                            try to_reprocess.append(allocator, s);
                        }

                        // Add the current remaining text
                        try to_reprocess.append(allocator, Segment.styledOptional(remaining_text, seg.style));

                        // Truncate result to just before the newline
                        result.shrinkRetainingCapacity(space_idx + 1);

                        // Insert newline
                        try result.append(allocator, Segment.line());
                        current_width = 0;
                        last_space_result_idx = null;

                        // Re-add all the segments that need to be re-wrapped
                        for (to_reprocess.items) |reprocess_seg| {
                            const rw = reprocess_seg.cellLength();
                            if (current_width + rw <= max_width) {
                                if (std.mem.lastIndexOfScalar(u8, reprocess_seg.text, ' ')) |_| {
                                    last_space_result_idx = result.items.len;
                                }
                                try result.append(allocator, reprocess_seg);
                                current_width += rw;
                            } else {
                                // Need to wrap this segment too - continue with inner loop logic
                                var inner_remaining = reprocess_seg.text;
                                while (inner_remaining.len > 0) {
                                    if (current_width >= max_width) {
                                        try result.append(allocator, Segment.line());
                                        current_width = 0;
                                        last_space_result_idx = null;
                                    }

                                    const inner_width = cells.cellLen(inner_remaining);
                                    const inner_avail = max_width - current_width;

                                    if (inner_width <= inner_avail) {
                                        if (std.mem.lastIndexOfScalar(u8, inner_remaining, ' ')) |_| {
                                            last_space_result_idx = result.items.len;
                                        }
                                        try result.append(allocator, Segment.styledOptional(inner_remaining, reprocess_seg.style));
                                        current_width += inner_width;
                                        break;
                                    }

                                    const inner_byte_limit = cells.cellToByteIndex(inner_remaining, inner_avail);
                                    var inner_break = inner_byte_limit;

                                    if (std.mem.lastIndexOfScalar(u8, inner_remaining[0..inner_byte_limit], ' ')) |inner_sp| {
                                        inner_break = inner_sp + 1;
                                    }

                                    if (inner_break > 0) {
                                        try result.append(allocator, Segment.styledOptional(inner_remaining[0..inner_break], reprocess_seg.style));
                                    }
                                    try result.append(allocator, Segment.line());
                                    inner_remaining = inner_remaining[inner_break..];
                                    current_width = 0;
                                    last_space_result_idx = null;
                                }
                            }
                        }

                        // Done with this segment, move to next in outer loop
                        remaining_text = "";
                        break;
                    }
                }

                // Output text up to break point
                if (break_byte > 0) {
                    const chunk = remaining_text[0..break_byte];
                    if (std.mem.lastIndexOfScalar(u8, chunk, ' ')) |_| {
                        last_space_result_idx = result.items.len;
                    }
                    try result.append(allocator, Segment.styledOptional(chunk, seg.style));
                    current_width += break_width;
                }

                // If we're at max width, insert newline
                if (current_width >= max_width or break_byte == byte_limit) {
                    try result.append(allocator, Segment.line());
                    current_width = 0;
                    last_space_result_idx = null;
                }

                remaining_text = remaining_text[break_byte..];
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

// Language auto-detection tests

// Line highlighting tests

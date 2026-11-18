const std = @import("std");
const Segment = @import("../../segment.zig").Segment;
const cells = @import("../../cells.zig");
const Syntax = @import("../syntax/mod.zig").Syntax;
const Language = @import("../syntax/mod.zig").Language;
const theme_mod = @import("theme.zig");
const HeaderLevel = theme_mod.HeaderLevel;
const MarkdownTheme = theme_mod.MarkdownTheme;

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

pub const CodeBlock = struct {
    code: []const u8,
    language: ?[]const u8 = null,
    theme: MarkdownTheme = .default,

    pub fn init(code: []const u8) CodeBlock {
        return .{ .code = code };
    }

    pub fn withLanguage(self: CodeBlock, lang: []const u8) CodeBlock {
        var cb = self;
        cb.language = lang;
        return cb;
    }

    pub fn withTheme(self: CodeBlock, theme: MarkdownTheme) CodeBlock {
        var cb = self;
        cb.theme = theme;
        return cb;
    }

    fn detectLanguage(self: CodeBlock) Language {
        const lang = self.language orelse return .plain;
        if (lang.len == 0) return .plain;

        const lang_map = std.StaticStringMap(Language).initComptime(.{
            .{ "zig", .zig },
            .{ "json", .json },
            .{ "md", .markdown },
            .{ "markdown", .markdown },
        });

        return lang_map.get(lang) orelse .plain;
    }

    pub fn render(self: CodeBlock, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        const detected_lang = self.detectLanguage();

        if (detected_lang != .plain) {
            const syntax = Syntax.init(allocator, self.code)
                .withLanguage(detected_lang)
                .withTheme(self.theme.syntax_theme);
            return syntax.renderDuped(max_width, allocator);
        }

        var segments: std.ArrayList(Segment) = .empty;
        var lines = std.mem.splitScalar(u8, self.code, '\n');

        while (lines.next()) |line| {
            if (line.len > 0) {
                const duped = try allocator.dupe(u8, line);
                try segments.append(allocator, Segment.styled(duped, self.theme.code_block_style));
            }
            try segments.append(allocator, Segment.line());
        }

        return segments.toOwnedSlice(allocator);
    }
};

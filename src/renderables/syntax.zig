const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const Color = @import("../color.zig").Color;
const cells = @import("../cells.zig");

pub const Language = enum {
    zig,
    json,
    markdown,
    plain,
};

pub const SyntaxTheme = struct {
    keyword_style: Style = Style.empty.foreground(Color.magenta).bold(),
    builtin_style: Style = Style.empty.foreground(Color.cyan),
    string_style: Style = Style.empty.foreground(Color.green),
    comment_style: Style = Style.empty.foreground(Color.default).dim(),
    number_style: Style = Style.empty.foreground(Color.yellow),
    operator_style: Style = Style.empty.foreground(Color.default),
    punctuation_style: Style = Style.empty.foreground(Color.default).dim(),
    type_style: Style = Style.empty.foreground(Color.blue),
    function_style: Style = Style.empty.foreground(Color.cyan),
    line_number_style: Style = Style.empty.foreground(Color.default).dim(),
    default_style: Style = Style.empty,

    pub const default: SyntaxTheme = .{};

    pub const monokai: SyntaxTheme = .{
        .keyword_style = Style.empty.foreground(Color.fromRgb(249, 38, 114)),
        .builtin_style = Style.empty.foreground(Color.fromRgb(102, 217, 239)),
        .string_style = Style.empty.foreground(Color.fromRgb(230, 219, 116)),
        .comment_style = Style.empty.foreground(Color.fromRgb(117, 113, 94)),
        .number_style = Style.empty.foreground(Color.fromRgb(174, 129, 255)),
        .operator_style = Style.empty.foreground(Color.fromRgb(249, 38, 114)),
        .punctuation_style = Style.empty.foreground(Color.fromRgb(248, 248, 242)),
        .type_style = Style.empty.foreground(Color.fromRgb(102, 217, 239)).italic(),
        .function_style = Style.empty.foreground(Color.fromRgb(166, 226, 46)),
        .line_number_style = Style.empty.foreground(Color.fromRgb(117, 113, 94)),
        .default_style = Style.empty.foreground(Color.fromRgb(248, 248, 242)),
    };

    pub const dracula: SyntaxTheme = .{
        .keyword_style = Style.empty.foreground(Color.fromRgb(255, 121, 198)),
        .builtin_style = Style.empty.foreground(Color.fromRgb(139, 233, 253)),
        .string_style = Style.empty.foreground(Color.fromRgb(241, 250, 140)),
        .comment_style = Style.empty.foreground(Color.fromRgb(98, 114, 164)),
        .number_style = Style.empty.foreground(Color.fromRgb(189, 147, 249)),
        .operator_style = Style.empty.foreground(Color.fromRgb(255, 121, 198)),
        .punctuation_style = Style.empty.foreground(Color.fromRgb(248, 248, 242)),
        .type_style = Style.empty.foreground(Color.fromRgb(139, 233, 253)).italic(),
        .function_style = Style.empty.foreground(Color.fromRgb(80, 250, 123)),
        .line_number_style = Style.empty.foreground(Color.fromRgb(98, 114, 164)),
        .default_style = Style.empty.foreground(Color.fromRgb(248, 248, 242)),
    };
};

const TokenType = enum {
    keyword,
    builtin,
    string,
    comment,
    number,
    operator,
    punctuation,
    type_name,
    function_name,
    default,
};

const zig_keywords = std.StaticStringMap(void).initComptime(.{
    .{ "const", {} },
    .{ "var", {} },
    .{ "fn", {} },
    .{ "pub", {} },
    .{ "return", {} },
    .{ "if", {} },
    .{ "else", {} },
    .{ "for", {} },
    .{ "while", {} },
    .{ "switch", {} },
    .{ "break", {} },
    .{ "continue", {} },
    .{ "defer", {} },
    .{ "errdefer", {} },
    .{ "try", {} },
    .{ "catch", {} },
    .{ "orelse", {} },
    .{ "and", {} },
    .{ "or", {} },
    .{ "error", {} },
    .{ "unreachable", {} },
    .{ "undefined", {} },
    .{ "null", {} },
    .{ "true", {} },
    .{ "false", {} },
    .{ "struct", {} },
    .{ "enum", {} },
    .{ "union", {} },
    .{ "packed", {} },
    .{ "extern", {} },
    .{ "export", {} },
    .{ "inline", {} },
    .{ "comptime", {} },
    .{ "test", {} },
    .{ "async", {} },
    .{ "await", {} },
    .{ "suspend", {} },
    .{ "resume", {} },
    .{ "anytype", {} },
    .{ "noreturn", {} },
    .{ "anyerror", {} },
    .{ "threadlocal", {} },
    .{ "linksection", {} },
    .{ "callconv", {} },
    .{ "noinline", {} },
    .{ "usingnamespace", {} },
    .{ "asm", {} },
    .{ "volatile", {} },
    .{ "allowzero", {} },
    .{ "align", {} },
});

const zig_builtins = std.StaticStringMap(void).initComptime(.{
    .{ "@import", {} },
    .{ "@as", {} },
    .{ "@intCast", {} },
    .{ "@floatCast", {} },
    .{ "@ptrCast", {} },
    .{ "@alignCast", {} },
    .{ "@enumFromInt", {} },
    .{ "@intFromEnum", {} },
    .{ "@intFromPtr", {} },
    .{ "@ptrFromInt", {} },
    .{ "@sizeOf", {} },
    .{ "@alignOf", {} },
    .{ "@typeInfo", {} },
    .{ "@TypeOf", {} },
    .{ "@This", {} },
    .{ "@tagName", {} },
    .{ "@errorName", {} },
    .{ "@fieldParentPtr", {} },
    .{ "@field", {} },
    .{ "@call", {} },
    .{ "@compileError", {} },
    .{ "@compileLog", {} },
    .{ "@panic", {} },
    .{ "@memcpy", {} },
    .{ "@memset", {} },
    .{ "@min", {} },
    .{ "@max", {} },
    .{ "@abs", {} },
    .{ "@mod", {} },
    .{ "@rem", {} },
    .{ "@sqrt", {} },
    .{ "@log", {} },
    .{ "@exp", {} },
    .{ "@sin", {} },
    .{ "@cos", {} },
    .{ "@tan", {} },
    .{ "@bitCast", {} },
    .{ "@truncate", {} },
    .{ "@ctz", {} },
    .{ "@clz", {} },
    .{ "@popCount", {} },
    .{ "@byteSwap", {} },
    .{ "@bitReverse", {} },
    .{ "@addWithOverflow", {} },
    .{ "@subWithOverflow", {} },
    .{ "@mulWithOverflow", {} },
    .{ "@shlWithOverflow", {} },
    .{ "@shlExact", {} },
    .{ "@shrExact", {} },
    .{ "@constCast", {} },
    .{ "@volatileCast", {} },
    .{ "@embedFile", {} },
    .{ "@cImport", {} },
    .{ "@cInclude", {} },
    .{ "@cDefine", {} },
    .{ "@cUndef", {} },
    .{ "@hasField", {} },
    .{ "@hasDecl", {} },
    .{ "@setRuntimeSafety", {} },
    .{ "@setFloatMode", {} },
    .{ "@setEvalBranchQuota", {} },
});

const zig_types = std.StaticStringMap(void).initComptime(.{
    .{ "void", {} },
    .{ "bool", {} },
    .{ "u8", {} },
    .{ "u16", {} },
    .{ "u32", {} },
    .{ "u64", {} },
    .{ "u128", {} },
    .{ "usize", {} },
    .{ "i8", {} },
    .{ "i16", {} },
    .{ "i32", {} },
    .{ "i64", {} },
    .{ "i128", {} },
    .{ "isize", {} },
    .{ "f16", {} },
    .{ "f32", {} },
    .{ "f64", {} },
    .{ "f128", {} },
    .{ "type", {} },
    .{ "comptime_int", {} },
    .{ "comptime_float", {} },
    .{ "anyframe", {} },
});

pub const Syntax = struct {
    code: []const u8,
    language: Language = .plain,
    theme: SyntaxTheme = SyntaxTheme.default,
    show_line_numbers: bool = false,
    start_line: usize = 1,
    allocator: std.mem.Allocator,

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

    pub fn render(self: Syntax, _: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        var lines = std.mem.splitScalar(u8, self.code, '\n');
        var line_num: usize = self.start_line;

        while (lines.next()) |line| {
            if (self.show_line_numbers) {
                var buf: [16]u8 = undefined;
                const line_str = std.fmt.bufPrint(&buf, "{d:>4} ", .{line_num}) catch "???? ";
                const line_str_copy = try allocator.dupe(u8, line_str);
                try segments.append(allocator, Segment.styled(line_str_copy, self.theme.line_number_style));
            }

            try self.highlightLine(&segments, allocator, line);
            try segments.append(allocator, Segment.line());
            line_num += 1;
        }

        return segments.toOwnedSlice(allocator);
    }

    fn highlightLine(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8) !void {
        switch (self.language) {
            .zig => try self.highlightZig(segments, allocator, line),
            .json => try self.highlightJson(segments, allocator, line),
            .markdown => try self.highlightMarkdown(segments, allocator, line),
            .plain => try segments.append(allocator, Segment.styledOptional(line, if (self.theme.default_style.isEmpty()) null else self.theme.default_style)),
        }
    }

    fn highlightZig(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8) !void {
        var i: usize = 0;

        while (i < line.len) {
            if (std.mem.startsWith(u8, line[i..], "//")) {
                try segments.append(allocator, Segment.styled(line[i..], self.theme.comment_style));
                return;
            }

            if (line[i] == '"') {
                const end = self.findStringEnd(line, i);
                try segments.append(allocator, Segment.styled(line[i..end], self.theme.string_style));
                i = end;
                continue;
            }

            if (line[i] == '\'') {
                const end = self.findCharEnd(line, i);
                try segments.append(allocator, Segment.styled(line[i..end], self.theme.string_style));
                i = end;
                continue;
            }

            if (line[i] == '@') {
                const end = self.findIdentEnd(line, i + 1);
                const builtin = line[i..end];
                if (zig_builtins.has(builtin)) {
                    try segments.append(allocator, Segment.styled(builtin, self.theme.builtin_style));
                } else {
                    try segments.append(allocator, Segment.styled(builtin, self.theme.default_style));
                }
                i = end;
                continue;
            }

            if (std.ascii.isDigit(line[i]) or (line[i] == '.' and i + 1 < line.len and std.ascii.isDigit(line[i + 1]))) {
                const end = self.findNumberEnd(line, i);
                try segments.append(allocator, Segment.styled(line[i..end], self.theme.number_style));
                i = end;
                continue;
            }

            if (std.ascii.isAlphabetic(line[i]) or line[i] == '_') {
                const end = self.findIdentEnd(line, i);
                const ident = line[i..end];

                if (zig_keywords.has(ident)) {
                    try segments.append(allocator, Segment.styled(ident, self.theme.keyword_style));
                } else if (zig_types.has(ident)) {
                    try segments.append(allocator, Segment.styled(ident, self.theme.type_style));
                } else if (end < line.len and line[end] == '(') {
                    try segments.append(allocator, Segment.styled(ident, self.theme.function_style));
                } else {
                    try segments.append(allocator, Segment.styledOptional(ident, if (self.theme.default_style.isEmpty()) null else self.theme.default_style));
                }
                i = end;
                continue;
            }

            if (self.isOperator(line[i])) {
                try segments.append(allocator, Segment.styled(line[i .. i + 1], self.theme.operator_style));
                i += 1;
                continue;
            }

            if (self.isPunctuation(line[i])) {
                try segments.append(allocator, Segment.styled(line[i .. i + 1], self.theme.punctuation_style));
                i += 1;
                continue;
            }

            try segments.append(allocator, Segment.styled(line[i .. i + 1], self.theme.default_style));
            i += 1;
        }
    }

    fn highlightJson(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8) !void {
        var i: usize = 0;

        while (i < line.len) {
            if (line[i] == '"') {
                const end = self.findStringEnd(line, i);
                const str_content = line[i..end];
                if (end < line.len and line[end] == ':') {
                    try segments.append(allocator, Segment.styled(str_content, self.theme.keyword_style));
                } else {
                    try segments.append(allocator, Segment.styled(str_content, self.theme.string_style));
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
                try segments.append(allocator, Segment.styled(kw, self.theme.keyword_style));
                i += kw.len;
                continue;
            }

            if (std.ascii.isDigit(line[i]) or (line[i] == '-' and i + 1 < line.len and std.ascii.isDigit(line[i + 1]))) {
                const end = self.findNumberEnd(line, i);
                try segments.append(allocator, Segment.styled(line[i..end], self.theme.number_style));
                i = end;
                continue;
            }

            if (self.isPunctuation(line[i])) {
                try segments.append(allocator, Segment.styled(line[i .. i + 1], self.theme.punctuation_style));
                i += 1;
                continue;
            }

            try segments.append(allocator, Segment.styled(line[i .. i + 1], self.theme.default_style));
            i += 1;
        }
    }

    fn highlightMarkdown(self: Syntax, segments: *std.ArrayList(Segment), allocator: std.mem.Allocator, line: []const u8) !void {
        if (line.len == 0) return;

        if (std.mem.startsWith(u8, line, "#")) {
            try segments.append(allocator, Segment.styled(line, self.theme.keyword_style.bold()));
            return;
        }

        if (std.mem.startsWith(u8, line, "```")) {
            try segments.append(allocator, Segment.styled(line, self.theme.comment_style));
            return;
        }

        if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ") or std.mem.startsWith(u8, line, "+ ")) {
            try segments.append(allocator, Segment.styled(line[0..2], self.theme.keyword_style));
            try segments.append(allocator, Segment.styledOptional(line[2..], if (self.theme.default_style.isEmpty()) null else self.theme.default_style));
            return;
        }

        if (std.mem.startsWith(u8, line, "> ")) {
            try segments.append(allocator, Segment.styled(line, self.theme.comment_style.italic()));
            return;
        }

        var i: usize = 0;
        while (i < line.len) {
            if (line[i] == '`') {
                var end = i + 1;
                while (end < line.len and line[end] != '`') : (end += 1) {}
                if (end < line.len) {
                    try segments.append(allocator, Segment.styled(line[i .. end + 1], self.theme.string_style));
                    i = end + 1;
                    continue;
                }
            }

            if (line[i] == '*' and i + 1 < line.len and line[i + 1] == '*') {
                var end = i + 2;
                while (end + 1 < line.len and !(line[end] == '*' and line[end + 1] == '*')) : (end += 1) {}
                if (end + 1 < line.len) {
                    try segments.append(allocator, Segment.styled(line[i .. end + 2], self.theme.keyword_style.bold()));
                    i = end + 2;
                    continue;
                }
            }

            if (line[i] == '*' or line[i] == '_') {
                const marker = line[i];
                var end = i + 1;
                while (end < line.len and line[end] != marker) : (end += 1) {}
                if (end < line.len) {
                    try segments.append(allocator, Segment.styled(line[i .. end + 1], self.theme.default_style.italic()));
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
                        try segments.append(allocator, Segment.styled(line[i .. paren_end + 1], self.theme.builtin_style));
                        i = paren_end + 1;
                        continue;
                    }
                }
            }

            try segments.append(allocator, Segment.styledOptional(line[i .. i + 1], if (self.theme.default_style.isEmpty()) null else self.theme.default_style));
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
};

test "Syntax.init" {
    const allocator = std.testing.allocator;
    const syntax = Syntax.init(allocator, "const x = 1;");
    try std.testing.expectEqualStrings("const x = 1;", syntax.code);
}

test "Syntax.withLanguage" {
    const allocator = std.testing.allocator;
    const syntax = Syntax.init(allocator, "code").withLanguage(.zig);
    try std.testing.expectEqual(Language.zig, syntax.language);
}

test "Syntax.withTheme" {
    const allocator = std.testing.allocator;
    const syntax = Syntax.init(allocator, "code").withTheme(SyntaxTheme.monokai);
    try std.testing.expect(syntax.theme.keyword_style.color != null);
}

test "Syntax.withLineNumbers" {
    const allocator = std.testing.allocator;
    const syntax = Syntax.init(allocator, "code").withLineNumbers();
    try std.testing.expect(syntax.show_line_numbers);
}

test "Syntax.render plain" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const syntax = Syntax.init(arena.allocator(), "Hello\nWorld");
    const segments = try syntax.render(80, arena.allocator());

    try std.testing.expect(segments.len > 0);
}

test "Syntax.render zig" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const code =
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    // comment
        \\    const x: u32 = 42;
        \\}
    ;
    const syntax = Syntax.init(arena.allocator(), code).withLanguage(.zig);
    const segments = try syntax.render(80, arena.allocator());

    try std.testing.expect(segments.len > 0);
}

test "Syntax.render zig with line numbers" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const syntax = Syntax.init(arena.allocator(), "const x = 1;\nconst y = 2;")
        .withLanguage(.zig)
        .withLineNumbers();
    const segments = try syntax.render(80, arena.allocator());

    var found_line_num = false;
    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "1") != null or std.mem.indexOf(u8, seg.text, "2") != null) {
            found_line_num = true;
            break;
        }
    }
    try std.testing.expect(found_line_num);
}

test "Syntax.render json" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const code =
        \\{
        \\  "name": "test",
        \\  "value": 42,
        \\  "active": true
        \\}
    ;
    const syntax = Syntax.init(arena.allocator(), code).withLanguage(.json);
    const segments = try syntax.render(80, arena.allocator());

    try std.testing.expect(segments.len > 0);
}

test "Syntax.render markdown" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const code =
        \\# Heading
        \\
        \\Some text with **bold** and *italic*.
        \\
        \\- List item
        \\
        \\```code block```
    ;
    const syntax = Syntax.init(arena.allocator(), code).withLanguage(.markdown);
    const segments = try syntax.render(80, arena.allocator());

    try std.testing.expect(segments.len > 0);
}

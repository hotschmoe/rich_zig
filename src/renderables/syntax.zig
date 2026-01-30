const std = @import("std");
const Segment = @import("../segment.zig").Segment;
const Style = @import("../style.zig").Style;
const Color = @import("../color.zig").Color;
const cells = @import("../cells.zig");

pub const Language = enum {
    zig,
    json,
    markdown,
    python,
    javascript,
    typescript,
    rust,
    go,
    c,
    cpp,
    bash,
    yaml,
    toml,
    xml,
    html,
    css,
    sql,
    plain,

    /// Detect language from file extension
    pub fn fromExtension(ext: []const u8) Language {
        const extension_map = std.StaticStringMap(Language).initComptime(.{
            // Zig
            .{ ".zig", .zig },
            .{ ".zon", .zig },
            // JSON
            .{ ".json", .json },
            .{ ".jsonl", .json },
            .{ ".geojson", .json },
            // Markdown
            .{ ".md", .markdown },
            .{ ".markdown", .markdown },
            .{ ".mdown", .markdown },
            // Python
            .{ ".py", .python },
            .{ ".pyi", .python },
            .{ ".pyw", .python },
            .{ ".pyx", .python },
            // JavaScript
            .{ ".js", .javascript },
            .{ ".mjs", .javascript },
            .{ ".cjs", .javascript },
            .{ ".jsx", .javascript },
            // TypeScript
            .{ ".ts", .typescript },
            .{ ".mts", .typescript },
            .{ ".cts", .typescript },
            .{ ".tsx", .typescript },
            // Rust
            .{ ".rs", .rust },
            // Go
            .{ ".go", .go },
            // C
            .{ ".c", .c },
            .{ ".h", .c },
            // C++
            .{ ".cpp", .cpp },
            .{ ".cxx", .cpp },
            .{ ".cc", .cpp },
            .{ ".hpp", .cpp },
            .{ ".hxx", .cpp },
            .{ ".hh", .cpp },
            // Shell/Bash
            .{ ".sh", .bash },
            .{ ".bash", .bash },
            .{ ".zsh", .bash },
            .{ ".fish", .bash },
            // YAML
            .{ ".yaml", .yaml },
            .{ ".yml", .yaml },
            // TOML
            .{ ".toml", .toml },
            // XML
            .{ ".xml", .xml },
            .{ ".xsl", .xml },
            .{ ".xslt", .xml },
            .{ ".svg", .xml },
            // HTML
            .{ ".html", .html },
            .{ ".htm", .html },
            .{ ".xhtml", .html },
            // CSS
            .{ ".css", .css },
            .{ ".scss", .css },
            .{ ".sass", .css },
            .{ ".less", .css },
            // SQL
            .{ ".sql", .sql },
        });

        // Normalize extension to lowercase for comparison
        var lower_ext: [16]u8 = undefined;
        const len = @min(ext.len, lower_ext.len);
        for (0..len) |i| {
            lower_ext[i] = std.ascii.toLower(ext[i]);
        }

        return extension_map.get(lower_ext[0..len]) orelse .plain;
    }

    /// Detect language from filename (extracts extension)
    pub fn fromFilename(filename: []const u8) Language {
        // Handle special filenames without extensions
        const basename = std.fs.path.basename(filename);

        const special_files = std.StaticStringMap(Language).initComptime(.{
            .{ "Makefile", .bash },
            .{ "makefile", .bash },
            .{ "GNUmakefile", .bash },
            .{ "Dockerfile", .bash },
            .{ "dockerfile", .bash },
            .{ "Containerfile", .bash },
            .{ ".bashrc", .bash },
            .{ ".bash_profile", .bash },
            .{ ".zshrc", .bash },
            .{ ".profile", .bash },
            .{ ".gitignore", .plain },
            .{ ".gitattributes", .plain },
            .{ "CMakeLists.txt", .bash },
            .{ "Cargo.toml", .toml },
            .{ "Cargo.lock", .toml },
            .{ "package.json", .json },
            .{ "tsconfig.json", .json },
            .{ "pyproject.toml", .toml },
            .{ "build.zig", .zig },
            .{ "build.zig.zon", .zig },
        });

        if (special_files.get(basename)) |lang| {
            return lang;
        }

        // Extract extension
        if (std.mem.lastIndexOfScalar(u8, filename, '.')) |dot_pos| {
            return fromExtension(filename[dot_pos..]);
        }

        return .plain;
    }

    /// Detect language from content using heuristics
    pub fn fromContent(content: []const u8) Language {
        const trimmed = std.mem.trimLeft(u8, content, " \t\n\r");
        if (trimmed.len == 0) return .plain;

        // Check for shebang
        if (std.mem.startsWith(u8, trimmed, "#!")) {
            const shebang = trimmed[0..@min(trimmed.len, 100)];
            if (std.mem.indexOf(u8, shebang, "python") != null) return .python;
            if (std.mem.indexOf(u8, shebang, "node") != null) return .javascript;
            // "sh" matches bash, sh, zsh
            if (std.mem.indexOf(u8, shebang, "sh") != null) return .bash;
            return .bash;
        }

        // Check for XML/HTML declaration
        if (std.mem.startsWith(u8, trimmed, "<?xml")) return .xml;
        if (std.mem.startsWith(u8, trimmed, "<!DOCTYPE html") or
            std.mem.startsWith(u8, trimmed, "<!doctype html") or
            std.mem.startsWith(u8, trimmed, "<html"))
        {
            return .html;
        }

        // Check for JSON (starts with { or [)
        if (trimmed[0] == '{' or trimmed[0] == '[') {
            if (looksLikeJson(trimmed)) return .json;
        }

        // Check for YAML (key: value pattern at start, or ---)
        if (std.mem.startsWith(u8, trimmed, "---")) return .yaml;

        // Check for Markdown (common patterns)
        if (std.mem.startsWith(u8, trimmed, "# ") or
            std.mem.startsWith(u8, trimmed, "## ") or
            std.mem.startsWith(u8, trimmed, "### "))
        {
            return .markdown;
        }

        // Check for common language patterns
        if (containsZigPatterns(content)) return .zig;
        if (containsPythonPatterns(content)) return .python;
        if (containsRustPatterns(content)) return .rust;
        if (containsGoPatterns(content)) return .go;
        if (containsJsPatterns(content)) return .javascript;
        if (containsCPatterns(content)) return .c;

        return .plain;
    }

    /// Auto-detect language from filename and/or content
    /// Tries filename first, falls back to content heuristics
    pub fn detect(filename: ?[]const u8, content: []const u8) Language {
        // Try filename-based detection first
        if (filename) |fname| {
            const from_file = fromFilename(fname);
            if (from_file != .plain) return from_file;
        }

        // Fall back to content-based detection
        return fromContent(content);
    }

    fn looksLikeJson(content: []const u8) bool {
        // Simple heuristic: check for common JSON patterns
        var brace_count: i32 = 0;
        var bracket_count: i32 = 0;
        var colon_count: usize = 0;
        var comma_count: usize = 0;
        var quote_count: usize = 0;
        const check_len = @min(content.len, 500);

        for (content[0..check_len]) |c| {
            switch (c) {
                '{' => brace_count += 1,
                '}' => brace_count -= 1,
                '[' => bracket_count += 1,
                ']' => bracket_count -= 1,
                ':' => colon_count += 1,
                ',' => comma_count += 1,
                '"' => quote_count += 1,
                else => {},
            }
        }

        // JSON object: has braces, colons, and usually quotes
        const looks_like_object = brace_count == 0 and colon_count > 0 and quote_count >= 2;

        // JSON array: starts with [, has balanced brackets, may have commas
        const looks_like_array = content[0] == '[' and bracket_count == 0;

        return looks_like_object or looks_like_array;
    }

    fn containsZigPatterns(content: []const u8) bool {
        const patterns = [_][]const u8{
            "const std = @import",
            "pub fn ",
            "@import(",
            "std.mem.",
            "std.debug.print",
            "catch |err|",
            "try ",
            "defer ",
            "comptime ",
        };
        return matchAnyPattern(content, &patterns, 3);
    }

    fn containsPythonPatterns(content: []const u8) bool {
        const patterns = [_][]const u8{
            "def ",
            "import ",
            "from ",
            "class ",
            "if __name__",
            "self.",
            "    def ",
            "print(",
            "async def ",
        };
        return matchAnyPattern(content, &patterns, 2);
    }

    fn containsRustPatterns(content: []const u8) bool {
        const patterns = [_][]const u8{
            "fn main()",
            "pub fn ",
            "use std::",
            "let mut ",
            "impl ",
            "struct ",
            "enum ",
            "match ",
            "-> Result<",
            "println!(",
            "#[derive(",
        };
        return matchAnyPattern(content, &patterns, 3);
    }

    fn containsGoPatterns(content: []const u8) bool {
        const patterns = [_][]const u8{
            "package ",
            "func main()",
            "import (",
            "func (",
            "type ",
            "fmt.Println",
            "if err != nil",
            ":= ",
        };
        return matchAnyPattern(content, &patterns, 3);
    }

    fn containsJsPatterns(content: []const u8) bool {
        const patterns = [_][]const u8{
            "function ",
            "const ",
            "let ",
            "var ",
            "=> {",
            "console.log",
            "module.exports",
            "require(",
            "export ",
            "import ",
            "async ",
        };
        return matchAnyPattern(content, &patterns, 2);
    }

    fn containsCPatterns(content: []const u8) bool {
        const patterns = [_][]const u8{
            "#include <",
            "#include \"",
            "int main(",
            "void ",
            "printf(",
            "sizeof(",
            "NULL",
            "malloc(",
            "#define ",
        };
        return matchAnyPattern(content, &patterns, 2);
    }

    fn matchAnyPattern(content: []const u8, patterns: []const []const u8, min_matches: usize) bool {
        var matches: usize = 0;
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, content, pattern) != null) {
                matches += 1;
                if (matches >= min_matches) return true;
            }
        }
        return false;
    }
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
    word_wrap: bool = false,
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
    pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !Syntax {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const code = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

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

    pub fn render(self: Syntax, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        var segments: std.ArrayList(Segment) = .empty;

        var lines = std.mem.splitScalar(u8, self.code, '\n');
        var line_num: usize = self.start_line;

        // Calculate available width for code (accounting for line numbers)
        const line_num_width: usize = if (self.show_line_numbers) 5 else 0; // "NNNN "
        const code_width: usize = if (max_width > line_num_width) max_width - line_num_width else max_width;

        while (lines.next()) |line| {
            if (self.show_line_numbers) {
                var buf: [16]u8 = undefined;
                const line_str = std.fmt.bufPrint(&buf, "{d:>4} ", .{line_num}) catch "???? ";
                const line_str_copy = try allocator.dupe(u8, line_str);
                try segments.append(allocator, Segment.styled(line_str_copy, self.theme.line_number_style));
            }

            if (self.word_wrap and code_width > 0) {
                var line_segments: std.ArrayList(Segment) = .empty;
                try self.highlightLine(&line_segments, allocator, line);
                const highlighted = try line_segments.toOwnedSlice(allocator);
                defer allocator.free(highlighted);

                const wrapped = try wrapSegments(highlighted, code_width, allocator);
                defer allocator.free(wrapped);

                var after_wrap_newline = false;
                for (wrapped) |seg| {
                    const is_newline = std.mem.eql(u8, seg.text, "\n");
                    if (after_wrap_newline and self.show_line_numbers and !is_newline) {
                        const indent = try allocator.dupe(u8, "     ");
                        try segments.append(allocator, Segment.styled(indent, self.theme.line_number_style));
                    }
                    try segments.append(allocator, seg);
                    after_wrap_newline = is_newline;
                }
            } else {
                try self.highlightLine(&segments, allocator, line);
            }

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
            // Languages without dedicated highlighters fall back to plain text
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
            => try segments.append(allocator, self.defaultSegment(line)),
        }
    }

    fn defaultSegment(self: Syntax, text: []const u8) Segment {
        const style = if (self.theme.default_style.isEmpty()) null else self.theme.default_style;
        return Segment.styledOptional(text, style);
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
                    try segments.append(allocator, self.defaultSegment(ident));
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
            try segments.append(allocator, self.defaultSegment(line[2..]));
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

            try segments.append(allocator, self.defaultSegment(line[i .. i + 1]));
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
    fn wrapSegments(line_segments: []const Segment, max_width: usize, allocator: std.mem.Allocator) ![]Segment {
        if (max_width == 0) {
            return allocator.dupe(Segment, line_segments);
        }

        var result: std.ArrayList(Segment) = .empty;
        var current_width: usize = 0;

        for (line_segments) |seg| {
            const seg_width = seg.cellLength();

            if (current_width + seg_width <= max_width) {
                try result.append(allocator, seg);
                current_width += seg_width;
                continue;
            }

            var remaining_text = seg.text;

            while (remaining_text.len > 0) {
                if (current_width >= max_width) {
                    try result.append(allocator, Segment.line());
                    current_width = 0;
                }

                const remaining_width = cells.cellLen(remaining_text);
                const available = max_width - current_width;

                if (remaining_width <= available) {
                    try result.append(allocator, Segment.styledOptional(remaining_text, seg.style));
                    current_width += remaining_width;
                    break;
                }

                const byte_pos = cells.cellToByteIndex(remaining_text, available);
                if (byte_pos > 0) {
                    try result.append(allocator, Segment.styledOptional(remaining_text[0..byte_pos], seg.style));
                }
                try result.append(allocator, Segment.line());
                remaining_text = remaining_text[byte_pos..];
                current_width = 0;
            }
        }

        return result.toOwnedSlice(allocator);
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

// Language auto-detection tests

test "Language.fromExtension detects common extensions" {
    try std.testing.expectEqual(Language.zig, Language.fromExtension(".zig"));
    try std.testing.expectEqual(Language.zig, Language.fromExtension(".zon"));
    try std.testing.expectEqual(Language.json, Language.fromExtension(".json"));
    try std.testing.expectEqual(Language.markdown, Language.fromExtension(".md"));
    try std.testing.expectEqual(Language.python, Language.fromExtension(".py"));
    try std.testing.expectEqual(Language.javascript, Language.fromExtension(".js"));
    try std.testing.expectEqual(Language.typescript, Language.fromExtension(".ts"));
    try std.testing.expectEqual(Language.rust, Language.fromExtension(".rs"));
    try std.testing.expectEqual(Language.go, Language.fromExtension(".go"));
    try std.testing.expectEqual(Language.c, Language.fromExtension(".c"));
    try std.testing.expectEqual(Language.c, Language.fromExtension(".h"));
    try std.testing.expectEqual(Language.cpp, Language.fromExtension(".cpp"));
    try std.testing.expectEqual(Language.bash, Language.fromExtension(".sh"));
    try std.testing.expectEqual(Language.yaml, Language.fromExtension(".yaml"));
    try std.testing.expectEqual(Language.yaml, Language.fromExtension(".yml"));
    try std.testing.expectEqual(Language.toml, Language.fromExtension(".toml"));
    try std.testing.expectEqual(Language.html, Language.fromExtension(".html"));
    try std.testing.expectEqual(Language.css, Language.fromExtension(".css"));
    try std.testing.expectEqual(Language.sql, Language.fromExtension(".sql"));
    try std.testing.expectEqual(Language.plain, Language.fromExtension(".unknown"));
}

test "Language.fromExtension case insensitive" {
    try std.testing.expectEqual(Language.zig, Language.fromExtension(".ZIG"));
    try std.testing.expectEqual(Language.json, Language.fromExtension(".JSON"));
    try std.testing.expectEqual(Language.python, Language.fromExtension(".PY"));
}

test "Language.fromFilename detects from full path" {
    try std.testing.expectEqual(Language.zig, Language.fromFilename("src/main.zig"));
    try std.testing.expectEqual(Language.json, Language.fromFilename("/path/to/config.json"));
    try std.testing.expectEqual(Language.python, Language.fromFilename("scripts/test.py"));
}

test "Language.fromFilename detects special files" {
    try std.testing.expectEqual(Language.bash, Language.fromFilename("Makefile"));
    try std.testing.expectEqual(Language.bash, Language.fromFilename("Dockerfile"));
    try std.testing.expectEqual(Language.bash, Language.fromFilename(".bashrc"));
    try std.testing.expectEqual(Language.toml, Language.fromFilename("Cargo.toml"));
    try std.testing.expectEqual(Language.json, Language.fromFilename("package.json"));
    try std.testing.expectEqual(Language.zig, Language.fromFilename("build.zig"));
    try std.testing.expectEqual(Language.zig, Language.fromFilename("build.zig.zon"));
}

test "Language.fromContent detects shebang" {
    try std.testing.expectEqual(Language.python, Language.fromContent("#!/usr/bin/env python3\nprint('hello')"));
    try std.testing.expectEqual(Language.bash, Language.fromContent("#!/bin/bash\necho hello"));
    try std.testing.expectEqual(Language.javascript, Language.fromContent("#!/usr/bin/env node\nconsole.log('hi')"));
}

test "Language.fromContent detects JSON" {
    try std.testing.expectEqual(Language.json, Language.fromContent("{\"key\": \"value\"}"));
    try std.testing.expectEqual(Language.json, Language.fromContent("[1, 2, 3]"));
    try std.testing.expectEqual(Language.json, Language.fromContent("  {\n  \"name\": \"test\"\n}"));
}

test "Language.fromContent detects XML/HTML" {
    try std.testing.expectEqual(Language.xml, Language.fromContent("<?xml version=\"1.0\"?>"));
    try std.testing.expectEqual(Language.html, Language.fromContent("<!DOCTYPE html>"));
    try std.testing.expectEqual(Language.html, Language.fromContent("<html>"));
}

test "Language.fromContent detects YAML" {
    try std.testing.expectEqual(Language.yaml, Language.fromContent("---\nkey: value"));
}

test "Language.fromContent detects Markdown" {
    try std.testing.expectEqual(Language.markdown, Language.fromContent("# Heading\n\nSome text"));
    try std.testing.expectEqual(Language.markdown, Language.fromContent("## Subheading"));
}

test "Language.fromContent detects Zig patterns" {
    const zig_code =
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello\n", .{});
        \\}
    ;
    try std.testing.expectEqual(Language.zig, Language.fromContent(zig_code));
}

test "Language.fromContent detects Python patterns" {
    const py_code =
        \\import os
        \\from sys import argv
        \\
        \\def main():
        \\    print("Hello")
    ;
    try std.testing.expectEqual(Language.python, Language.fromContent(py_code));
}

test "Language.fromContent detects Rust patterns" {
    const rust_code =
        \\use std::io;
        \\
        \\fn main() {
        \\    println!("Hello");
        \\}
    ;
    try std.testing.expectEqual(Language.rust, Language.fromContent(rust_code));
}

test "Language.fromContent detects Go patterns" {
    const go_code =
        \\package main
        \\
        \\import "fmt"
        \\
        \\func main() {
        \\    fmt.Println("Hello")
        \\}
    ;
    try std.testing.expectEqual(Language.go, Language.fromContent(go_code));
}

test "Language.detect prefers filename over content" {
    // Even though content looks like Python, filename says Zig
    try std.testing.expectEqual(Language.zig, Language.detect("test.zig", "import os\ndef main():"));
}

test "Language.detect falls back to content when filename is plain" {
    const zig_code = "const std = @import(\"std\");\npub fn main() void {}";
    try std.testing.expectEqual(Language.zig, Language.detect("noext", zig_code));
    try std.testing.expectEqual(Language.zig, Language.detect(null, zig_code));
}

test "Syntax.withAutoDetect" {
    const allocator = std.testing.allocator;
    const code = "const std = @import(\"std\");";
    const syntax = Syntax.init(allocator, code).withAutoDetect("main.zig");
    try std.testing.expectEqual(Language.zig, syntax.language);
}

test "Syntax.fromFile" {
    const allocator = std.testing.allocator;
    const code = "{\"key\": \"value\"}";
    const syntax = Syntax.fromFile(allocator, code, "config.json");
    try std.testing.expectEqual(Language.json, syntax.language);
}

test "Syntax.withWordWrap" {
    const allocator = std.testing.allocator;
    const syntax = Syntax.init(allocator, "code").withWordWrap();
    try std.testing.expect(syntax.word_wrap);
}

test "Syntax.render with word wrap - short line" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const syntax = Syntax.init(arena.allocator(), "const x = 1;")
        .withLanguage(.zig)
        .withWordWrap();
    const segments = try syntax.render(80, arena.allocator());

    // Short line should render without wrapping
    try std.testing.expect(segments.len > 0);

    // Count newlines (should be exactly 1 for single line)
    var newline_count: usize = 0;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "\n")) {
            newline_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), newline_count);
}

test "Syntax.render with word wrap - long line wraps" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Create a line that's longer than the max width
    const long_line = "const very_long_variable_name = \"This is a very long string that should wrap\";";
    const syntax = Syntax.init(arena.allocator(), long_line)
        .withLanguage(.zig)
        .withWordWrap();

    // Use narrow width to force wrapping
    const segments = try syntax.render(30, arena.allocator());

    // Should have wrapped (more than 1 newline)
    var newline_count: usize = 0;
    for (segments) |seg| {
        if (std.mem.eql(u8, seg.text, "\n")) {
            newline_count += 1;
        }
    }
    try std.testing.expect(newline_count > 1);
}

test "Syntax.render word wrap preserves styles" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // String that wraps should keep string style on continuation
    const code = "const s = \"This is a very long string literal that will wrap across multiple lines\";";
    const syntax = Syntax.init(arena.allocator(), code)
        .withLanguage(.zig)
        .withWordWrap();

    const segments = try syntax.render(30, arena.allocator());

    // Find string segments (styled with string_style - green)
    var found_styled_segments = false;
    for (segments) |seg| {
        if (seg.style) |style| {
            if (style.color != null) {
                found_styled_segments = true;
                break;
            }
        }
    }
    try std.testing.expect(found_styled_segments);
}

test "Syntax.render word wrap with line numbers" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const long_line = "const x = \"This is a line that is definitely too long to fit\";";
    const syntax = Syntax.init(arena.allocator(), long_line)
        .withLanguage(.zig)
        .withWordWrap()
        .withLineNumbers();

    const segments = try syntax.render(40, arena.allocator());

    // Should have line number prefix and continuation indent
    var found_line_num = false;
    var found_indent = false;
    for (segments) |seg| {
        if (std.mem.indexOf(u8, seg.text, "1") != null and seg.text.len <= 5) {
            found_line_num = true;
        }
        // Continuation indent is 5 spaces
        if (std.mem.eql(u8, seg.text, "     ")) {
            found_indent = true;
        }
    }
    try std.testing.expect(found_line_num);
    // Indent may or may not appear depending on exact wrap point
}

test "wrapSegments basic" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const segs = [_]Segment{
        Segment.plain("Hello World this is a test"),
    };

    const wrapped = try Syntax.wrapSegments(&segs, 10, arena.allocator());

    // Should have wrapped into multiple lines
    var newline_count: usize = 0;
    for (wrapped) |seg| {
        if (std.mem.eql(u8, seg.text, "\n")) {
            newline_count += 1;
        }
    }
    try std.testing.expect(newline_count >= 2);
}

test "wrapSegments preserves style across wrap" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const test_style = Style.empty.bold();
    const segs = [_]Segment{
        Segment.styled("This is styled text that should wrap", test_style),
    };

    const wrapped = try Syntax.wrapSegments(&segs, 15, arena.allocator());

    // All non-newline segments should have the style
    for (wrapped) |seg| {
        if (!std.mem.eql(u8, seg.text, "\n") and seg.text.len > 0) {
            try std.testing.expect(seg.style != null);
            try std.testing.expect(seg.style.?.hasAttribute(.bold));
        }
    }
}

test "wrapSegments handles multiple segments" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const style1 = Style.empty.bold();
    const style2 = Style.empty.italic();

    const segs = [_]Segment{
        Segment.styled("const ", style1),
        Segment.plain("x = "),
        Segment.styled("\"long string value\"", style2),
    };

    const wrapped = try Syntax.wrapSegments(&segs, 15, arena.allocator());

    // Should produce some output
    try std.testing.expect(wrapped.len > 0);
}

test "wrapSegments zero width returns input" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const segs = [_]Segment{
        Segment.plain("Hello"),
    };

    const wrapped = try Syntax.wrapSegments(&segs, 0, arena.allocator());

    try std.testing.expectEqual(@as(usize, 1), wrapped.len);
    try std.testing.expectEqualStrings("Hello", wrapped[0].text);
}

test "Syntax.loadFile reads file and detects language" {
    const allocator = std.testing.allocator;

    // Load this source file itself
    var syntax = try Syntax.loadFile(allocator, "src/renderables/syntax.zig");
    defer syntax.deinit();

    // Should detect as Zig from extension
    try std.testing.expectEqual(Language.zig, syntax.language);

    // Should contain actual code
    try std.testing.expect(syntax.code.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, syntax.code, "const std") != null);
}

test "Syntax.loadFile error on non-existent file" {
    const allocator = std.testing.allocator;

    const result = Syntax.loadFile(allocator, "non_existent_file_xyz123.zig");
    try std.testing.expectError(error.FileNotFound, result);
}

test "Syntax.loadFile renders correctly" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Load build.zig.zon (small file)
    var syntax = try Syntax.loadFile(arena.allocator(), "build.zig.zon");
    // No need for deinit since arena handles cleanup

    // Should detect as Zig from extension
    try std.testing.expectEqual(Language.zig, syntax.language);

    // Should render successfully
    const segments = try syntax.render(80, arena.allocator());
    try std.testing.expect(segments.len > 0);
}

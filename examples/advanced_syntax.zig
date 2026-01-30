//! Advanced Syntax Example - Themes, tab size, indent guides, line highlighting
//!
//! Run with: zig build example-advanced_syntax

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Syntax with Monokai theme
    try console.print("[bold]Syntax with Monokai Theme:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const code = "const x: u32 = 42;\nconst msg = \"hello\";";
        const syntax = rich.Syntax.init(arena.allocator(), code)
            .withLanguage(.zig)
            .withTheme(rich.SyntaxTheme.monokai);
        try console.printRenderable(syntax);
    }
    try console.print("");

    // Syntax with custom tab size
    try console.print("[bold]Syntax with Custom Tab Size (2 spaces):[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const code = "fn foo() void {\n\tbar();\n\tbaz();\n}";
        const syntax = rich.Syntax.init(arena.allocator(), code)
            .withLanguage(.zig)
            .withTabSize(2);
        try console.printRenderable(syntax);
    }
    try console.print("");

    // Syntax with indent guides
    try console.print("[bold]Syntax with Indent Guides:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const code =
            \\pub fn main() void {
            \\    if (true) {
            \\        doSomething();
            \\        if (nested) {
            \\            deeper();
            \\        }
            \\    }
            \\}
        ;
        const syntax = rich.Syntax.init(arena.allocator(), code)
            .withLanguage(.zig)
            .withIndentGuides();
        try console.printRenderable(syntax);
    }
    try console.print("");

    // Syntax with highlighted lines
    try console.print("[bold]Syntax with Highlighted Line (line 2):[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const code =
            \\const a = 1;
            \\const b = 2;  // <-- This line highlighted
            \\const c = 3;
        ;
        const highlight_lines = [_]usize{2};
        const syntax = rich.Syntax.init(arena.allocator(), code)
            .withLanguage(.zig)
            .withLineNumbers()
            .withHighlightLines(&highlight_lines);
        try console.printRenderable(syntax);
    }
    try console.print("");

    // Syntax with word wrap (manual render to demo specific width)
    try console.print("[bold]Syntax with Word Wrap (width=45):[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const long_code = "const very_long_variable_name: u32 = some_function_call(argument1, argument2, argument3);";
        const syntax = rich.Syntax.init(arena.allocator(), long_code)
            .withLanguage(.zig)
            .withWordWrap();
        const segs = try syntax.render(45, arena.allocator());
        try console.printSegments(segs);
    }
    try console.print("");

    // Language auto-detection from file extension
    try console.print("[bold]Language Auto-Detection:[/]");
    const extensions = [_][]const u8{ ".py", ".rs", ".zig", ".js", ".go", ".c" };
    var buf: [64]u8 = undefined;
    for (extensions) |ext| {
        const lang = rich.SyntaxLanguage.fromExtension(ext);
        const line = std.fmt.bufPrint(&buf, "  {s} -> {s}", .{ ext, @tagName(lang) }) catch continue;
        try console.printPlain(line);
    }
}

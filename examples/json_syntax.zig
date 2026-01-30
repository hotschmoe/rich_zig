//! JSON and Syntax Highlighting Example
//!
//! Run with: zig build example-json_syntax

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // JSON rendering - use fromString to parse JSON text
    try console.print("[bold]JSON Rendering:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const json_str =
            \\{
            \\  "name": "rich_zig",
            \\  "version": "0.10.0",
            \\  "features": ["panels", "tables", "trees"],
            \\  "active": true,
            \\  "downloads": 12345
            \\}
        ;

        var json = try rich.Json.fromString(arena.allocator(), json_str);
        json.indent = 2;
        try console.printRenderable(json);
    }
    try console.print("");

    // JSON with custom theme
    try console.print("[bold]JSON with Custom Theme:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const json_str =
            \\{"status": "ok", "count": 42, "enabled": false}
        ;

        var json = try rich.Json.fromString(arena.allocator(), json_str);
        json = json.withTheme(.{
            .string_style = rich.Style.empty.foreground(rich.Color.green),
            .number_style = rich.Style.empty.foreground(rich.Color.yellow),
            .bool_style = rich.Style.empty.foreground(rich.Color.magenta),
            .null_style = rich.Style.empty.foreground(rich.Color.red),
            .key_style = rich.Style.empty.bold().foreground(rich.Color.cyan),
        });
        try console.printRenderable(json);
    }
    try console.print("");

    // Syntax highlighting for Zig code
    try console.print("[bold]Zig Syntax Highlighting:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const zig_code =
            \\const std = @import("std");
            \\
            \\pub fn main() !void {
            \\    const message = "Hello, World!";
            \\    std.debug.print("{s}\n", .{message});
            \\}
        ;

        var syntax = rich.Syntax.init(arena.allocator(), zig_code).withLanguage(.zig);
        syntax.show_line_numbers = true;
        try console.printRenderable(syntax);
    }
    try console.print("");

    // Syntax highlighting for Python
    try console.print("[bold]Python Syntax Highlighting:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const python_code =
            \\def greet(name: str) -> str:
            \\    """Return a greeting message."""
            \\    return f"Hello, {name}!"
            \\
            \\if __name__ == "__main__":
            \\    print(greet("World"))
        ;

        var syntax = rich.Syntax.init(arena.allocator(), python_code).withLanguage(.python);
        syntax.show_line_numbers = true;
        try console.printRenderable(syntax);
    }
    try console.print("");

    // Markdown rendering
    try console.print("[bold]Markdown Rendering:[/]");
    {
        const markdown_text =
            \\# rich_zig
            \\
            \\A **beautiful** terminal formatting library for _Zig_.
            \\
            \\## Features
            \\
            \\- Styled text with colors
            \\- Tables and panels
            \\- Progress bars
            \\
            \\```zig
            \\const rich = @import("rich_zig");
            \\```
        ;

        const md = rich.Markdown.init(markdown_text);
        try console.printRenderable(md);
    }
}

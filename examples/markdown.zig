//! Markdown Example - Full markdown rendering with GFM extensions
//!
//! Run with: zig build example-markdown

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Markdown Example").withCharacters("="));
    try console.print("");

    // Headers
    try console.print("[bold]Markdown Headers:[/]");
    {
        const md = rich.Markdown.init("# Heading 1\n## Heading 2\n### Heading 3");
        try console.printRenderable(md);
    }
    try console.print("");

    // Inline styles
    try console.print("[bold]Inline Styles:[/]");
    {
        const md = rich.Markdown.init("This has **bold**, *italic*, and ***bold italic*** text.");
        try console.printRenderable(md);
    }
    {
        const md = rich.Markdown.init("Also works with __bold__ and _italic_ using underscores.");
        try console.printRenderable(md);
    }
    try console.print("");

    // Inline code
    try console.print("[bold]Inline Code:[/]");
    {
        const md = rich.Markdown.init("Use `std.debug.print` for debugging in Zig.");
        try console.printRenderable(md);
    }
    try console.print("");

    // Links
    try console.print("[bold]Links:[/]");
    {
        const md = rich.Markdown.init("Check out [rich_zig](https://github.com/example/rich_zig) for details.");
        try console.printRenderable(md);
    }
    try console.print("");

    // Horizontal rule
    try console.print("[bold]Horizontal Rule:[/]");
    {
        const md = rich.Markdown.init("Above\n\n---\n\nBelow");
        try console.printRenderable(md);
    }
    try console.print("");

    // Lists
    try console.print("[bold]Lists:[/]");
    {
        const md = rich.Markdown.init("- First item\n- Second item\n- Third item\n\n1. Numbered one\n2. Numbered two\n3. Numbered three");
        try console.printRenderable(md);
    }
    try console.print("");

    // Blockquotes
    try console.print("[bold]Blockquotes:[/]");
    {
        const md = rich.Markdown.init("> This is a quote\n> with multiple lines\n>> Nested quote");
        try console.printRenderable(md);
    }
    try console.print("");

    // Fenced code block
    try console.print("[bold]Fenced Code Block:[/]");
    {
        const md = rich.Markdown.init("```zig\nconst x: u32 = 42;\nstd.debug.print(\"{}\", .{x});\n```");
        try console.printRenderable(md);
    }
    try console.print("");

    // GFM: Strikethrough
    try console.print("[bold]GFM Strikethrough:[/]");
    {
        const md = rich.Markdown.init("This has ~~strikethrough~~ formatting.");
        try console.printRenderable(md);
    }
    try console.print("");

    // GFM: Task lists
    try console.print("[bold]GFM Task Lists:[/]");
    {
        const md = rich.Markdown.init("- [x] Completed task\n- [ ] Pending task\n- [x] Another done");
        try console.printRenderable(md);
    }
    try console.print("");

    // GFM: Tables
    try console.print("[bold]GFM Tables:[/]");
    {
        const md = rich.Markdown.init("| Name | Value |\n|------|-------|\n| foo  | 123   |\n| bar  | 456   |");
        try console.printRenderable(md);
    }
    try console.print("");

    // Images (alt text display)
    try console.print("[bold]Images (Alt Text):[/]");
    {
        const md = rich.Markdown.init("Here's an image: ![Logo](https://example.com/logo.png)");
        try console.printRenderable(md);
    }
}

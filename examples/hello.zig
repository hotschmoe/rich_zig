//! Hello World Example - Console basics, markup, and styles
//!
//! Run with: zig build example-hello

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Hello Example").withCharacters("="));
    try console.print("");

    // Basic styled text with BBCode-like markup
    try console.print("Hello, [bold cyan]rich_zig[/]!");
    try console.print("");

    // Multiple styles can be combined
    try console.print("[bold]Bold[/] and [italic]italic[/] and [underline]underline[/]");
    try console.print("[bold italic underline]All three at once[/]");
    try console.print("");

    // Color examples
    try console.print("[red]Red[/] [green]Green[/] [blue]Blue[/] [yellow]Yellow[/]");
    try console.print("[magenta]Magenta[/] [cyan]Cyan[/] [white]White[/]");
    try console.print("");

    // Background colors with "on" keyword
    try console.print("[white on red] Error [/] Something went wrong");
    try console.print("[black on yellow] Warning [/] Check your configuration");
    try console.print("[white on green] Success [/] Operation completed");
    try console.print("");

    // Dim and strikethrough
    try console.print("[dim]This text is dimmed[/]");
    try console.print("[strikethrough]This text is struck through[/]");
    try console.print("");

    // Nested styles
    try console.print("[bold]Bold with [red]red[/red] inside[/bold]");
    try console.print("");

    // Using Text for programmatic styling
    const Style = rich.Style;
    const Color = rich.Color;

    // Build styled text using fromMarkup
    var styled = try rich.Text.fromMarkup(allocator, "[bold green]Programmatic[/] [italic cyan]styling[/] example");
    defer styled.deinit();

    const segments = try styled.render(allocator);
    defer allocator.free(segments);
    try console.printSegments(segments);

    // Or use direct segment creation for simple cases
    try console.print("");
    const manual_segments = [_]rich.Segment{
        rich.Segment.styled("Direct ", Style.empty.bold()),
        rich.Segment.styled("segment ", Style.empty.foreground(Color.yellow)),
        rich.Segment.styled("creation", Style.empty.italic().foreground(Color.cyan)),
    };
    try console.printSegments(&manual_segments);
    try console.print("");
}

//! Progress Example - Progress bars and spinners
//!
//! Run with: zig build example-progress

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Basic progress bar
    try console.print("[bold]Basic Progress Bar:[/]");
    {
        const bar = rich.ProgressBar.init()
            .withCompleted(60)
            .withTotal(100)
            .withWidth(40);

        const segments = try bar.render(80, allocator);
        defer allocator.free(segments);
        try console.printSegments(segments);
    }
    try console.print("");

    // Progress bar with description
    try console.print("[bold]Progress Bar with Description:[/]");
    {
        const bar = rich.ProgressBar.init()
            .withDescription("Downloading...")
            .withCompleted(75)
            .withTotal(100)
            .withWidth(30);

        const segments = try bar.render(80, allocator);
        defer allocator.free(segments);
        try console.printSegments(segments);
    }
    try console.print("");

    // Multiple progress bars at different stages
    try console.print("[bold]Progress at Different Stages:[/]");
    const stages = [_]u64{ 0, 25, 50, 75, 100 };
    for (stages) |completed| {
        const bar = rich.ProgressBar.init()
            .withCompleted(completed)
            .withTotal(100)
            .withWidth(30);

        const segments = try bar.render(80, allocator);
        defer allocator.free(segments);
        try console.printSegments(segments);
    }
    try console.print("");

    // Progress group for multiple concurrent tasks
    try console.print("[bold]Progress Group (Multiple Tasks):[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var group = rich.ProgressGroup.init(arena.allocator());

        // Add all tasks first
        _ = try group.addTask("Download", 100);
        _ = try group.addTask("Extract", 100);
        _ = try group.addTask("Install", 100);

        // Then update progress (pointers from addTask can be invalidated by subsequent adds)
        group.bars.items[0].completed = 100;
        group.bars.items[1].completed = 60;
        group.bars.items[2].completed = 20;

        const segs = try group.render(80, arena.allocator());
        try console.printSegments(segs);
    }
    try console.print("");

    // Spinner examples
    try console.print("[bold]Spinners:[/]");
    {
        // Default spinner (braille dots)
        const default_spinner = rich.Spinner.init();
        const default_segs = try default_spinner.render(allocator);
        defer allocator.free(default_segs);
        try console.printSegments(default_segs);
        try console.print(" Default (braille)");

        // Dots spinner variant
        const dots_spinner = rich.Spinner.dots();
        const dots_segs = try dots_spinner.render(allocator);
        defer allocator.free(dots_segs);
        try console.printSegments(dots_segs);
        try console.print(" Dots variant");

        // Line spinner
        const line_spinner = rich.Spinner.line();
        const line_segs = try line_spinner.render(allocator);
        defer allocator.free(line_segs);
        try console.printSegments(line_segs);
        try console.print(" Line variant");

        // Spinner with style
        const styled_spinner = rich.Spinner.init().withStyle(rich.Style.empty.bold().foreground(rich.Color.cyan));
        const styled_segs = try styled_spinner.render(allocator);
        defer allocator.free(styled_segs);
        try console.printSegments(styled_segs);
        try console.print(" Styled spinner");
    }
}

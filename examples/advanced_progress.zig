//! Advanced Progress Example - Timing info, indeterminate progress
//!
//! Run with: zig build example-advanced_progress

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.printRenderable(rich.Rule.init().withTitle("Advanced Progress Example").withCharacters("="));
    try console.print("");

    // Progress bar with timing information
    try console.print("[bold]Progress with Timing Info:[/]");
    {
        const bar = rich.ProgressBar.init()
            .withDescription("Downloading")
            .withCompleted(75)
            .withTotal(100)
            .withWidth(25)
            .withTiming();
        try console.printRenderable(bar);
    }
    try console.print("");

    // Indeterminate progress bar (unknown total)
    try console.print("[bold]Indeterminate Progress (unknown total):[/]");
    {
        const bar = rich.ProgressBar.init()
            .withDescription("Scanning")
            .asIndeterminate()
            .withWidth(25);
        try console.printRenderable(bar);
    }
    try console.print("");

    // Multiple progress bars at different completion levels
    try console.print("[bold]Progress at Different Stages:[/]");
    {
        const stages = [_]struct { desc: []const u8, completed: u64 }{
            .{ .desc = "Critical", .completed = 90 },
            .{ .desc = "Warning", .completed = 60 },
            .{ .desc = "Normal", .completed = 30 },
        };

        for (stages) |s| {
            const bar = rich.ProgressBar.init()
                .withDescription(s.desc)
                .withCompleted(s.completed)
                .withTotal(100)
                .withWidth(20);
            try console.printRenderable(bar);
        }
    }
    try console.print("");

    // Progress group with mixed states
    try console.print("[bold]Progress Group with Mixed States:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var group = rich.ProgressGroup.init(arena.allocator());

        _ = try group.addTask("Complete", 100);
        _ = try group.addTask("In Progress", 100);
        _ = try group.addTask("Starting", 100);
        _ = try group.addTask("Pending", 100);

        group.bars.items[0].completed = 100;
        group.bars.items[1].completed = 65;
        group.bars.items[2].completed = 10;
        group.bars.items[3].completed = 0;

        try console.printRenderable(group);
    }
}

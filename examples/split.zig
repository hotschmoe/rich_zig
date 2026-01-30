//! Split Layout Example - Vertical and horizontal region splitting
//!
//! Run with: zig build example-split

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Vertical split (stacked regions)
    try console.print("[bold]Vertical Split (Top/Bottom):[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const top = [_]rich.Segment{
            rich.Segment.styled("[ Top Region ]", rich.Style.empty.bold().foreground(rich.Color.cyan)),
        };
        const bottom = [_]rich.Segment{
            rich.Segment.styled("[ Bottom Region ]", rich.Style.empty.dim()),
        };

        var split = rich.Split.vertical(arena.allocator());
        _ = split.add(&top).add(&bottom);

        const segs = try split.render(40, arena.allocator());
        try console.printSegments(segs);
    }
    try console.print("");

    // Horizontal split (side-by-side regions)
    try console.print("[bold]Horizontal Split (Left/Right):[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const left = [_]rich.Segment{
            rich.Segment.styled("[Left]", rich.Style.empty.foreground(rich.Color.green)),
        };
        const right = [_]rich.Segment{
            rich.Segment.styled("[Right]", rich.Style.empty.foreground(rich.Color.yellow)),
        };

        var split = rich.Split.horizontal(arena.allocator());
        _ = split.add(&left).add(&right);

        const segs = try split.render(40, arena.allocator());
        try console.printSegments(segs);
    }
    try console.print("");

    // Multiple vertical regions
    try console.print("[bold]Multiple Vertical Regions:[/]");
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const header = [_]rich.Segment{
            rich.Segment.styled("=== HEADER ===", rich.Style.empty.bold()),
        };
        const content = [_]rich.Segment{
            rich.Segment.plain("Main content area"),
        };
        const footer = [_]rich.Segment{
            rich.Segment.styled("--- footer ---", rich.Style.empty.dim()),
        };

        var split = rich.Split.vertical(arena.allocator());
        _ = split.add(&header).add(&content).add(&footer);

        const segs = try split.render(40, arena.allocator());
        try console.printSegments(segs);
    }
}

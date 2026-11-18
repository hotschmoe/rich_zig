const std = @import("std");
const rich = @import("rich_zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var console = rich.Console.init(allocator, io, init.minimal.environ);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Layout Example").withCharacters("="));
    try console.print("");

    try console.print("[bold]Padding:[/]");
    {
        const panel = rich.Panel.fromText(allocator, "Original content")
            .withTitle("No Padding")
            .withWidth(30);
        const panel_segments = try panel.render(80, allocator);
        defer allocator.free(panel_segments);
        try console.printSegments(panel_segments);

        const content_segments = [_]rich.Segment{
            rich.Segment.plain("Padded content here"),
        };
        const padded = rich.Padding.init(&content_segments).withPadding(1, 4, 1, 4);
        const padded_segments = try padded.render(40, allocator);
        defer allocator.free(padded_segments);
        try console.print("With Padding (1,4,1,4):");
        try console.printSegments(padded_segments);
    }
    try console.print("");

    try console.print("[bold]Alignment:[/]");
    {
        const content = [_]rich.Segment{rich.Segment.plain("Centered text")};

        const centered = rich.Align.init(&content).center().withWidth(50);
        const centered_segments = try centered.render(60, allocator);
        defer allocator.free(centered_segments);
        try console.print("Center aligned:");
        try console.printSegments(centered_segments);

        const right_content = [_]rich.Segment{rich.Segment.plain("Right aligned text")};
        const right_aligned = rich.Align.init(&right_content).right().withWidth(50);
        const right_segments = try right_aligned.render(60, allocator);
        defer allocator.free(right_segments);
        try console.print("Right aligned:");
        try console.printSegments(right_segments);
    }
    try console.print("");

    try console.print("[bold]Columns:[/]");
    {
        const col1 = [_]rich.Segment{rich.Segment.plain("Column 1")};
        const col2 = [_]rich.Segment{rich.Segment.plain("Column 2")};
        const col3 = [_]rich.Segment{rich.Segment.plain("Column 3")};
        const items = [_][]const rich.Segment{ &col1, &col2, &col3 };

        const columns = rich.Columns.init(allocator, &items);
        const col_segments = try columns.render(80, allocator);
        defer allocator.free(col_segments);
        try console.printSegments(col_segments);
    }
    try console.print("");

    try console.print("[bold]Rule Divider:[/]");
    {
        const rule = rich.Rule.init()
            .withTitle("Section Break")
            .withCharacters("=");
        try console.printRenderable(rule);
    }
}

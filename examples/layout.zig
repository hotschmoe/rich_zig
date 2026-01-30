//! Layout Example - Align, Padding, Columns, and Split
//!
//! Run with: zig build example-layout

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Padding example - Padding wraps segments, not renderables
    try console.print("[bold]Padding:[/]");
    {
        // First render the panel to get segments
        const panel = rich.Panel.fromText(allocator, "Original content")
            .withTitle("No Padding")
            .withWidth(30);
        const panel_segments = try panel.render(80, allocator);
        defer allocator.free(panel_segments);
        try console.printSegments(panel_segments);

        // Pad the panel content using segment-based Padding
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

    // Alignment example - Align wraps segments
    try console.print("[bold]Alignment:[/]");
    {
        // Create simple content to align
        const content = [_]rich.Segment{rich.Segment.plain("Centered text")};

        // Center align
        const centered = rich.Align.init(&content).center().withWidth(50);
        const centered_segments = try centered.render(60, allocator);
        defer allocator.free(centered_segments);
        try console.print("Center aligned:");
        try console.printSegments(centered_segments);

        // Right align
        const right_content = [_]rich.Segment{rich.Segment.plain("Right aligned text")};
        const right_aligned = rich.Align.init(&right_content).right().withWidth(50);
        const right_segments = try right_aligned.render(60, allocator);
        defer allocator.free(right_segments);
        try console.print("Right aligned:");
        try console.printSegments(right_segments);
    }
    try console.print("");

    // Columns example - Columns takes pre-rendered segment arrays
    try console.print("[bold]Columns:[/]");
    {
        // Columns works with segment arrays - use fromText for simple text columns
        const texts = [_][]const u8{ "Column 1", "Column 2", "Column 3" };
        const columns = try rich.Columns.fromText(allocator, &texts);
        const col_segments = try columns.render(80, allocator);
        defer allocator.free(col_segments);
        try console.printSegments(col_segments);
    }
    try console.print("");

    // Split layout example - Split takes segments, not renderables directly
    try console.print("[bold]Split Layout (Horizontal):[/]");
    {
        // Pre-render panels to get segments
        const left_panel = rich.Panel.fromText(allocator, "Left side content")
            .withTitle("Left")
            .withWidth(35);
        const left_segs = try left_panel.render(80, allocator);
        defer allocator.free(left_segs);

        const right_panel = rich.Panel.fromText(allocator, "Right side content")
            .withTitle("Right")
            .withWidth(35);
        const right_segs = try right_panel.render(80, allocator);
        defer allocator.free(right_segs);

        var split = rich.Split.horizontal(allocator);
        defer split.deinit();
        _ = split.add(left_segs);
        _ = split.add(right_segs);

        const split_segs = try split.render(80, allocator);
        defer allocator.free(split_segs);
        try console.printSegments(split_segs);
    }
    try console.print("");

    // Rule as a divider
    try console.print("[bold]Rule Divider:[/]");
    {
        const rule = rich.Rule.init()
            .withTitle("Section Break")
            .withCharacters("=");
        try console.printRenderable(rule);
    }
}

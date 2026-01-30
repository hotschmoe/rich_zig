//! Advanced Panel Example - Title alignment, height constraints, custom boxes
//!
//! Run with: zig build example-advanced_panel

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Panel with left-aligned title
    try console.print("[bold]Title Alignment - Left:[/]");
    {
        const panel = rich.Panel.fromText(allocator, "Content with left-aligned title")
            .withTitle("Left Title")
            .withTitleAlignment(.left)
            .withWidth(40);
        try console.printRenderable(panel);
    }
    try console.print("");

    // Panel with center-aligned title (default)
    try console.print("[bold]Title Alignment - Center:[/]");
    {
        const panel = rich.Panel.fromText(allocator, "Content with centered title")
            .withTitle("Center Title")
            .withTitleAlignment(.center)
            .withWidth(40);
        try console.printRenderable(panel);
    }
    try console.print("");

    // Panel with right-aligned title
    try console.print("[bold]Title Alignment - Right:[/]");
    {
        const panel = rich.Panel.fromText(allocator, "Content with right-aligned title")
            .withTitle("Right Title")
            .withTitleAlignment(.right)
            .withWidth(40);
        try console.printRenderable(panel);
    }
    try console.print("");

    // Panel with height constraint
    try console.print("[bold]Panel with Height Constraint (max 4 lines):[/]");
    {
        const panel = rich.Panel.fromText(allocator, "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6")
            .withTitle("Clipped Content")
            .withHeight(4)
            .withVerticalOverflow(.ellipsis)
            .withWidth(35);
        try console.printRenderable(panel);
    }
    try console.print("");

    // Custom box style
    try console.print("[bold]Custom Box Style:[/]");
    {
        const custom_box = rich.BoxStyle.custom(.{
            .top_left = "*",
            .top_right = "*",
            .bottom_left = "*",
            .bottom_right = "*",
            .horizontal = "=",
            .vertical = "!",
        });

        // Display the custom box manually
        const horiz = try custom_box.getHorizontal(20, allocator);
        defer allocator.free(horiz);

        const segments = [_]rich.Segment{
            rich.Segment.plain(custom_box.top_left),
            rich.Segment.plain(horiz),
            rich.Segment.plain(custom_box.top_right),
            rich.Segment.plain("\n"),
            rich.Segment.plain(custom_box.vertical),
            rich.Segment.plain("   Custom Box!     "),
            rich.Segment.plain(custom_box.vertical),
            rich.Segment.plain("\n"),
            rich.Segment.plain(custom_box.bottom_left),
            rich.Segment.plain(horiz),
            rich.Segment.plain(custom_box.bottom_right),
            rich.Segment.plain("\n"),
        };
        try console.printSegments(&segments);
    }
    try console.print("");

    // Padding with background style
    try console.print("[bold]Padding with Background Style:[/]");
    {
        const content = [_]rich.Segment{rich.Segment.plain("Padded content")};
        const bg_style = rich.Style.empty.background(rich.Color.fromRgb(60, 60, 80));
        const padding = rich.Padding.init(&content).uniform(1).withStyle(bg_style);
        try console.printRenderable(padding);
    }
}

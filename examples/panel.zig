//! Panel Example - Panels, semantic constructors, and box styles
//!
//! Run with: zig build example-panel

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // Basic panel
    const basic = rich.Panel.fromText(allocator, "This is a basic panel with default styling.");
    try console.printRenderable(basic);
    try console.print("");

    // Panel with title and subtitle
    const titled = rich.Panel.fromText(allocator, "Panels can have titles and subtitles for better organization.")
        .withTitle("My Panel")
        .withSubtitle("A helpful subtitle");
    try console.printRenderable(titled);
    try console.print("");

    // Panel with custom width
    const narrow = rich.Panel.fromText(allocator, "This panel has a fixed width.")
        .withTitle("Narrow Panel")
        .withWidth(40);
    try console.printRenderable(narrow);
    try console.print("");

    // Semantic panels - pre-styled for common use cases
    try console.print("[bold]Semantic Panels:[/]");
    try console.print("");

    const info = rich.Panel.info(allocator, "Database connection established successfully.");
    try console.printRenderable(info);

    const warning = rich.Panel.warning(allocator, "Cache size is approaching the configured limit.");
    try console.printRenderable(warning);

    const err_panel = rich.Panel.err(allocator, "Failed to load configuration file.");
    try console.printRenderable(err_panel);

    const success = rich.Panel.success(allocator, "Build completed with no errors.");
    try console.printRenderable(success);
    try console.print("");

    // Different box styles - use the fluent methods
    try console.print("[bold]Box Styles:[/]");
    try console.print("");

    const ascii_panel = rich.Panel.fromText(allocator, "ASCII box style")
        .withTitle("ASCII")
        .ascii()
        .withWidth(30);
    try console.printRenderable(ascii_panel);

    const rounded_panel = rich.Panel.fromText(allocator, "Rounded box style")
        .withTitle("Rounded")
        .rounded()
        .withWidth(30);
    try console.printRenderable(rounded_panel);

    const double_panel = rich.Panel.fromText(allocator, "Double box style")
        .withTitle("Double")
        .double()
        .withWidth(30);
    try console.printRenderable(double_panel);

    const heavy_panel = rich.Panel.fromText(allocator, "Heavy box style")
        .withTitle("Heavy")
        .heavy()
        .withWidth(30);
    try console.printRenderable(heavy_panel);
}

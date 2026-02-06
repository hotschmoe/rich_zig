const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Demo 1: New style attributes (underline2, frame, encircle)
    std.debug.print("\n=== Demo 1: New Style Attributes ===\n", .{});

    var console1 = rich.Console.init(allocator);
    defer console1.deinit();

    try console1.print("[underline2]Double underlined text[/]");
    try console1.print("[uu red]Short form double underline[/]");
    try console1.print("[frame blue]Framed text[/]");
    try console1.print("[encircle green]Encircled text[/]");
    try console1.print("[hidden]This text is concealed[/] - hidden is an alias for conceal");

    // Demo 2: Theme system
    std.debug.print("\n=== Demo 2: Theme System ===\n", .{});

    // Create a default theme
    var theme = try rich.Theme.default(allocator);
    defer theme.deinit();

    // Create console with theme
    var console2 = rich.Console.initWithOptions(allocator, .{
        .theme = theme,
    });
    defer console2.deinit();

    try console2.print("[info]This is informational text[/]");
    try console2.print("[warning]This is a warning message[/]");
    try console2.print("[error]This is an error message[/]");
    try console2.print("[success]Operation completed successfully[/]");

    try console2.print("\nData type highlighting:");
    try console2.print("[repr.number]42[/] [repr.string]\"hello\"[/] [repr.bool]true[/]");
    try console2.print("[repr.url]https://example.com[/]");
    try console2.print("[repr.path]/home/user/file.txt[/]");

    try console2.print("\nLog levels:");
    try console2.print("[log.debug]Debug message[/]");
    try console2.print("[log.info]Info message[/]");
    try console2.print("[log.warning]Warning message[/]");
    try console2.print("[log.error]Error message[/]");

    try console2.print("\nStructural:");
    try console2.print("[title]Main Title[/]");
    try console2.print("[subtitle]Subtitle text[/]");
    try console2.print("[header]Header Text[/]");
    try console2.print("[muted]Muted/dimmed text[/]");
    try console2.print("[link]Click here[/]");

    // Demo 3: Custom theme
    std.debug.print("\n=== Demo 3: Custom Theme ===\n", .{});

    var custom_theme = rich.Theme.init(allocator);
    defer custom_theme.deinit();

    // Define custom styles
    try custom_theme.define("brand", rich.Style.empty.bold().foreground(rich.Color.fromRgb(255, 100, 50)));
    try custom_theme.define("highlight", rich.Style.empty.underline2().foreground(rich.Color.cyan));
    try custom_theme.define("special", rich.Style.empty.frame().foreground(rich.Color.magenta));

    var console3 = rich.Console.initWithOptions(allocator, .{
        .theme = custom_theme,
    });
    defer console3.deinit();

    try console3.print("[brand]Our Brand Text[/]");
    try console3.print("[highlight]Highlighted with double underline[/]");
    try console3.print("[special]Special framed text[/]");

    // Demo 4: Theme merging
    std.debug.print("\n=== Demo 4: Theme Merging ===\n", .{});

    var base_theme = try rich.Theme.default(allocator);
    defer base_theme.deinit();

    var overlay_theme = rich.Theme.init(allocator);
    defer overlay_theme.deinit();

    // Override the default "error" style
    try overlay_theme.define("error", rich.Style.empty.bold().encircle().foreground(rich.Color.fromRgb(255, 0, 100)));

    // Merge overlay into base
    try base_theme.merge(overlay_theme);

    var console4 = rich.Console.initWithOptions(allocator, .{
        .theme = base_theme,
    });
    defer console4.deinit();

    try console4.print("[error]This error has a custom style (encircled)[/]");
    try console4.print("[info]Info still uses default style[/]");

    std.debug.print("\n=== All demos completed successfully! ===\n", .{});
}

const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    _ = rich.terminal.enableUtf8();
    _ = rich.terminal.enableVirtualTerminal();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    // -- Header --
    const header = rich.Panel.fromText(allocator, "rich_zig v1.4.0 - Color Features Demo")
        .withTitle("Color Features")
        .withWidth(60);
    try console.printRenderable(header);
    try console.print("");

    // -- 1. Adaptive Colors --
    try console.print("[bold cyan]1. Adaptive Colors[/]");
    try console.printPlain("   Colors that auto-downgrade to match terminal capabilities.");
    try console.print("");

    const sunset = rich.AdaptiveColor.init(
        rich.Color.fromRgb(255, 100, 50),
        rich.Color.from256(208),
        rich.Color.yellow,
    );

    const color_systems = [_]struct { name: []const u8, sys: rich.ColorSystem }{
        .{ .name = "truecolor", .sys = .truecolor },
        .{ .name = "eight_bit", .sys = .eight_bit },
        .{ .name = "standard ", .sys = .standard },
    };

    var buf: [512]u8 = undefined;
    for (color_systems) |cs| {
        const resolved = sunset.resolve(cs.sys);
        var ansi_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&ansi_buf);
        const style = rich.Style.empty.foreground(resolved);
        try style.renderAnsi(cs.sys, stream.writer());
        const line = std.fmt.bufPrint(&buf, "   {s}: {s}sunset orange\x1b[0m", .{ cs.name, stream.getWritten() }) catch "";
        try console.printPlain(line);
    }

    const auto_ac = rich.AdaptiveColor.fromRgb(0, 180, 255);
    const auto_resolved = auto_ac.resolve(.standard);
    const auto_line = std.fmt.bufPrint(&buf, "   auto-downgrade: RGB(0,180,255) -> standard color #{d}", .{auto_resolved.number.?}) catch "";
    try console.printPlain(auto_line);
    try console.print("");

    // -- 2. HSL Blending --
    try console.print("[bold cyan]2. HSL Color Blending[/]");
    try console.printPlain("   Perceptually smooth transitions through the color wheel.");
    try console.print("");

    const red_c = rich.ColorTriplet{ .r = 255, .g = 0, .b = 0 };
    const green_c = rich.ColorTriplet{ .r = 0, .g = 255, .b = 0 };

    // RGB blend line
    var big_buf: [2048]u8 = undefined;
    var pos: usize = 0;
    const rgb_prefix = "   RGB blend (red->green): ";
    @memcpy(big_buf[pos..][0..rgb_prefix.len], rgb_prefix);
    pos += rgb_prefix.len;

    for (0..20) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / 19.0;
        const c = rich.ColorTriplet.blend(red_c, green_c, t);
        const written = std.fmt.bufPrint(big_buf[pos..], "\x1b[48;2;{d};{d};{d}m \x1b[0m", .{ c.r, c.g, c.b }) catch break;
        pos += written.len;
    }
    try console.printPlain(big_buf[0..pos]);

    // HSL blend line
    pos = 0;
    const hsl_prefix = "   HSL blend (red->green): ";
    @memcpy(big_buf[pos..][0..hsl_prefix.len], hsl_prefix);
    pos += hsl_prefix.len;

    for (0..20) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / 19.0;
        const c = rich.ColorTriplet.blendHsl(red_c, green_c, t);
        const written = std.fmt.bufPrint(big_buf[pos..], "\x1b[48;2;{d};{d};{d}m \x1b[0m", .{ c.r, c.g, c.b }) catch break;
        pos += written.len;
    }
    try console.printPlain(big_buf[0..pos]);
    try console.print("");

    // -- 3. Multi-Stop Gradient --
    try console.print("[bold cyan]3. Multi-Stop Gradient[/]");
    try console.printPlain("   Generate N colors across multiple color stops.");
    try console.print("");

    const stops = [_]rich.ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 255, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 255, .g = 0, .b = 255 },
    };

    var rgb_grad: [50]rich.ColorTriplet = undefined;
    var hsl_grad: [50]rich.ColorTriplet = undefined;
    rich.gradient(&stops, &rgb_grad, false);
    rich.gradient(&stops, &hsl_grad, true);

    // RGB gradient
    pos = 0;
    const rgb_grad_prefix = "   RGB gradient: ";
    @memcpy(big_buf[pos..][0..rgb_grad_prefix.len], rgb_grad_prefix);
    pos += rgb_grad_prefix.len;
    for (rgb_grad) |c| {
        const written = std.fmt.bufPrint(big_buf[pos..], "\x1b[48;2;{d};{d};{d}m \x1b[0m", .{ c.r, c.g, c.b }) catch break;
        pos += written.len;
    }
    try console.printPlain(big_buf[0..pos]);

    // HSL gradient
    pos = 0;
    const hsl_grad_prefix = "   HSL gradient: ";
    @memcpy(big_buf[pos..][0..hsl_grad_prefix.len], hsl_grad_prefix);
    pos += hsl_grad_prefix.len;
    for (hsl_grad) |c| {
        const written = std.fmt.bufPrint(big_buf[pos..], "\x1b[48;2;{d};{d};{d}m \x1b[0m", .{ c.r, c.g, c.b }) catch break;
        pos += written.len;
    }
    try console.printPlain(big_buf[0..pos]);
    try console.print("");

    // -- 4. WCAG Contrast --
    try console.print("[bold cyan]4. WCAG Contrast Ratio[/]");
    try console.printPlain("   Accessibility-aware color pair validation.");
    try console.print("");

    const pairs = [_]struct { name: []const u8, fg: rich.ColorTriplet, bg: rich.ColorTriplet }{
        .{ .name = "Black on White ", .fg = .{ .r = 0, .g = 0, .b = 0 }, .bg = .{ .r = 255, .g = 255, .b = 255 } },
        .{ .name = "White on Black ", .fg = .{ .r = 255, .g = 255, .b = 255 }, .bg = .{ .r = 0, .g = 0, .b = 0 } },
        .{ .name = "Gray on White  ", .fg = .{ .r = 128, .g = 128, .b = 128 }, .bg = .{ .r = 255, .g = 255, .b = 255 } },
        .{ .name = "Red on Black   ", .fg = .{ .r = 255, .g = 0, .b = 0 }, .bg = .{ .r = 0, .g = 0, .b = 0 } },
        .{ .name = "Yellow on White", .fg = .{ .r = 255, .g = 255, .b = 0 }, .bg = .{ .r = 255, .g = 255, .b = 255 } },
    };

    for (pairs) |p| {
        const ratio = p.fg.contrastRatio(p.bg);
        const level = p.fg.wcagLevel(p.bg);
        const level_str = switch (level) {
            .aaa => "AAA     ",
            .aa => "AA      ",
            .aa_large => "AA-large",
            .fail => "FAIL    ",
        };
        const line = std.fmt.bufPrint(&big_buf, "   \x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m {s} \x1b[0m  ratio: {d:.1}:1  level: {s}", .{
            p.fg.r, p.fg.g, p.fg.b,
            p.bg.r, p.bg.g, p.bg.b,
            p.name, ratio,  level_str,
        }) catch "";
        try console.printPlain(line);
    }
    try console.print("");

    // -- 5. Synchronized Output --
    try console.print("[bold cyan]5. Synchronized Output[/]");
    try console.printPlain("   Atomic frame rendering with DEC mode 2026.");
    try console.print("");

    const info = rich.terminal.detect();
    const sync_str = std.fmt.bufPrint(&buf, "   Terminal sync support: {s}", .{if (info.supports_sync_output) "yes" else "no"}) catch "";
    try console.printPlain(sync_str);
    try console.printPlain("   Sequence: ESC[?2026h (begin) / ESC[?2026l (end)");
    try console.print("");

    // -- 6. Background Detection --
    try console.print("[bold cyan]6. Dark Background Detection[/]");
    try console.print("");

    const mode_str = switch (info.background_mode) {
        .dark => "dark",
        .light => "light",
        .unknown => "unknown",
    };
    const bg_str = std.fmt.bufPrint(&buf, "   Detected background: {s}", .{mode_str}) catch "";
    try console.printPlain(bg_str);
    try console.print("");
}

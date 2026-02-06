//! Color Features Example - Adaptive colors, HSL blending, gradients, WCAG contrast
//!
//! Run with: zig build example-color_features

const std = @import("std");
const rich = @import("rich_zig");

fn writeColorBar(writer: anytype, colors: []const rich.ColorTriplet) void {
    for (colors) |c| {
        writer.print("\x1b[48;2;{d};{d};{d}m \x1b[0m", .{ c.r, c.g, c.b }) catch return;
    }
}

pub fn main() !void {
    _ = rich.terminal.enableUtf8();
    _ = rich.terminal.enableVirtualTerminal();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich.Console.init(allocator);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich.Rule.init().withTitle("Color Features").withCharacters("="));
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

    var buf: [512]u8 = undefined;
    const systems = [_]struct { name: []const u8, sys: rich.ColorSystem }{
        .{ .name = "truecolor", .sys = .truecolor },
        .{ .name = "eight_bit", .sys = .eight_bit },
        .{ .name = "standard ", .sys = .standard },
    };

    for (systems) |cs| {
        const resolved = sunset.resolve(cs.sys);
        var ansi_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&ansi_buf);
        try rich.Style.empty.foreground(resolved).renderAnsi(cs.sys, stream.writer());
        const line = std.fmt.bufPrint(&buf, "   {s}: {s}sunset orange\x1b[0m", .{ cs.name, stream.getWritten() }) catch continue;
        try console.printPlain(line);
    }

    const auto_resolved = rich.AdaptiveColor.fromRgb(0, 180, 255).resolve(.standard);
    const auto_line = std.fmt.bufPrint(&buf, "   auto-downgrade: RGB(0,180,255) -> standard color #{d}", .{auto_resolved.number.?}) catch "";
    try console.printPlain(auto_line);
    try console.print("");

    // -- 2. HSL Blending --
    try console.print("[bold cyan]2. HSL Color Blending[/]");
    try console.printPlain("   Perceptually smooth transitions through the color wheel.");
    try console.print("");

    const red_c = rich.ColorTriplet{ .r = 255, .g = 0, .b = 0 };
    const green_c = rich.ColorTriplet{ .r = 0, .g = 255, .b = 0 };

    var blend_rgb: [20]rich.ColorTriplet = undefined;
    var blend_hsl: [20]rich.ColorTriplet = undefined;
    for (0..20) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / 19.0;
        blend_rgb[i] = rich.ColorTriplet.blend(red_c, green_c, t);
        blend_hsl[i] = rich.ColorTriplet.blendHsl(red_c, green_c, t);
    }

    var big_buf: [2048]u8 = undefined;
    var stream = std.io.fixedBufferStream(&big_buf);
    var writer = stream.writer();

    writer.writeAll("   RGB blend (red->green): ") catch {};
    writeColorBar(writer, &blend_rgb);
    try console.printPlain(stream.getWritten());

    stream.reset();
    writer.writeAll("   HSL blend (red->green): ") catch {};
    writeColorBar(writer, &blend_hsl);
    try console.printPlain(stream.getWritten());
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

    stream.reset();
    writer.writeAll("   RGB gradient: ") catch {};
    writeColorBar(writer, &rgb_grad);
    try console.printPlain(stream.getWritten());

    stream.reset();
    writer.writeAll("   HSL gradient: ") catch {};
    writeColorBar(writer, &hsl_grad);
    try console.printPlain(stream.getWritten());
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
        const level_str: []const u8 = switch (p.fg.wcagLevel(p.bg)) {
            .aaa => "AAA     ",
            .aa => "AA      ",
            .aa_large => "AA-large",
            .fail => "FAIL    ",
        };
        stream.reset();
        writer.print("   \x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m {s} \x1b[0m  ratio: {d:.1}:1  level: {s}", .{
            p.fg.r, p.fg.g, p.fg.b,
            p.bg.r, p.bg.g, p.bg.b,
            p.name, ratio,  level_str,
        }) catch continue;
        try console.printPlain(stream.getWritten());
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
    try console.print("[bold cyan]6. Background Detection[/]");
    try console.print("");

    const mode_str: []const u8 = switch (info.background_mode) {
        .dark => "dark",
        .light => "light",
        .unknown => "unknown",
    };
    const bg_str = std.fmt.bufPrint(&buf, "   Detected background: {s}", .{mode_str}) catch "";
    try console.printPlain(bg_str);
    try console.print("");
}

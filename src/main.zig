const std = @import("std");
const rich = @import("rich_zig");

pub fn main() !void {
    // Enable UTF-8 output on Windows
    _ = rich.terminal.enableUtf8();
    _ = rich.terminal.enableVirtualTerminal();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try stdout.writeAll("rich_zig v0.7.0 - Full Demo\n");
    try stdout.writeAll("===========================\n\n");

    // Phase 1: Color, Style, Segment
    try stdout.writeAll("Phase 1: Core Foundation\n");
    try stdout.writeAll("------------------------\n");

    // Color examples
    try stdout.writeAll("Colors:\n");
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try rich.Color.red.getAnsiCodes(true, stream.writer());
    try stdout.print("  \x1b[{s}mRed text\x1b[0m\n", .{stream.getWritten()});

    stream.reset();
    try rich.Color.fromRgb(255, 128, 64).getAnsiCodes(true, stream.writer());
    try stdout.print("  \x1b[{s}mRGB(255,128,64)\x1b[0m\n", .{stream.getWritten()});

    // Style examples
    try stdout.writeAll("\nStyles:\n");
    const bold_red = rich.Style.empty.bold().foreground(rich.Color.red);
    try bold_red.renderAnsi(.truecolor, stdout);
    try stdout.writeAll("  Bold red");
    try rich.Style.renderReset(stdout);
    try stdout.writeAll("\n");

    const parsed = try rich.Style.parse("bold underline blue");
    try parsed.renderAnsi(.truecolor, stdout);
    try stdout.writeAll("  Parsed: bold underline blue");
    try rich.Style.renderReset(stdout);
    try stdout.writeAll("\n");

    // Cell width
    try stdout.writeAll("\nCell widths:\n");
    try stdout.print("  \"Hello\" = {d} cells\n", .{rich.cells.cellLen("Hello")});
    try stdout.print("  CJK = {d} cells\n", .{rich.cells.cellLen("\u{4E2D}\u{6587}")});

    // Phase 2: Text and Markup
    try stdout.writeAll("\nPhase 2: Text and Markup\n");
    try stdout.writeAll("------------------------\n");

    var text = try rich.Text.fromMarkup(allocator, "[bold red]Hello[/] [italic green]World[/]!");
    defer text.deinit();

    const segments = try text.render(allocator);
    defer allocator.free(segments);

    try stdout.writeAll("Markup: ");
    for (segments) |seg| {
        try seg.render(stdout, .truecolor);
    }
    try stdout.writeAll("\n");

    // Box styles
    try stdout.writeAll("\nBox styles:\n");
    const box_styles = [_]struct { name: []const u8, style: rich.BoxStyle }{
        .{ .name = "rounded", .style = rich.BoxStyle.rounded },
        .{ .name = "square", .style = rich.BoxStyle.square },
        .{ .name = "heavy", .style = rich.BoxStyle.heavy },
        .{ .name = "double", .style = rich.BoxStyle.double },
        .{ .name = "ascii", .style = rich.BoxStyle.ascii },
    };

    for (box_styles) |bs| {
        try stdout.print("  {s}: {s}{s}{s}{s}{s}\n", .{
            bs.name,
            bs.style.top_left,
            bs.style.horizontal,
            bs.style.horizontal,
            bs.style.horizontal,
            bs.style.top_right,
        });
    }

    // Phase 3: Terminal and Console
    try stdout.writeAll("\nPhase 3: Terminal and Console\n");
    try stdout.writeAll("-----------------------------\n");

    const term_info = rich.terminal.detect();
    try stdout.print("Terminal: {d}x{d}, color={s}, tty={}\n", .{
        term_info.width,
        term_info.height,
        @tagName(term_info.color_system),
        term_info.is_tty,
    });

    // Console
    var console = rich.Console.init(allocator);
    defer console.deinit();
    try stdout.print("Console width: {d}\n", .{console.width()});

    // Phase 4: Renderables
    try stdout.writeAll("\nPhase 4: Renderables\n");
    try stdout.writeAll("--------------------\n");

    // Panel
    try stdout.writeAll("\nPanel:\n");
    const panel = rich.Panel.fromText(allocator, "Panel content").withTitle("Title").withWidth(30);
    const panel_segs = try panel.render(80, allocator);
    defer allocator.free(panel_segs);
    for (panel_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // Rule
    try stdout.writeAll("\nRule:\n");
    const rule = rich.Rule.init().withTitle("Section");
    const rule_segs = try rule.render(30, allocator);
    defer allocator.free(rule_segs);
    for (rule_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // Progress bar
    try stdout.writeAll("\nProgress bar (50%):\n");
    const bar = rich.ProgressBar.init().withCompleted(50).withTotal(100).withWidth(30);
    const bar_segs = try bar.render(80, allocator);
    defer allocator.free(bar_segs);
    for (bar_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }
    try stdout.writeAll("\n");

    // Spinner
    try stdout.writeAll("\nSpinner frames: ");
    var spinner = rich.Spinner.init();
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const spin_segs = try spinner.render(allocator);
        defer allocator.free(spin_segs);
        for (spin_segs) |seg| {
            try seg.render(stdout, .truecolor);
        }
        try stdout.writeAll(" ");
        spinner.advance();
    }
    try stdout.writeAll("\n");

    // Tree
    try stdout.writeAll("\nTree:\n");
    var root = rich.TreeNode.init(allocator, "root");
    defer root.deinit();
    const child1 = try root.addChildLabel("child1");
    _ = try child1.addChildLabel("grandchild");
    _ = try root.addChildLabel("child2");

    const tree = rich.Tree.init(root);
    const tree_segs = try tree.render(80, allocator);
    defer allocator.free(tree_segs);
    for (tree_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // Table
    try stdout.writeAll("\nTable:\n");
    var table = rich.Table.init(allocator);
    defer table.deinit();
    _ = table.addColumn("Name").addColumn("Value");
    try table.addRow(&.{ "foo", "123" });
    try table.addRow(&.{ "bar", "456" });

    const table_segs = try table.render(40, allocator);
    defer allocator.free(table_segs);
    for (table_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // v0.7.0 Features
    try stdout.writeAll("\nv0.7.0 New Features\n");
    try stdout.writeAll("-------------------\n");

    // Panel with title alignment
    try stdout.writeAll("\nPanel with left-aligned title:\n");
    const panel_left = rich.Panel.fromText(allocator, "Left title").withTitle("Left").withTitleAlignment(.left).withWidth(30);
    const panel_left_segs = try panel_left.render(80, allocator);
    defer allocator.free(panel_left_segs);
    for (panel_left_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    try stdout.writeAll("\nPanel with right-aligned title:\n");
    const panel_right = rich.Panel.fromText(allocator, "Right title").withTitle("Right").withTitleAlignment(.right).withWidth(30);
    const panel_right_segs = try panel_right.render(80, allocator);
    defer allocator.free(panel_right_segs);
    for (panel_right_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // Table with caption
    try stdout.writeAll("\nTable with caption:\n");
    var table2 = rich.Table.init(allocator);
    defer table2.deinit();
    _ = table2.addColumn("Item").addColumn("Price").withCaption("Shopping List");
    try table2.addRow(&.{ "Apple", "$1.50" });
    try table2.addRow(&.{ "Bread", "$2.00" });

    const table2_segs = try table2.render(40, allocator);
    defer allocator.free(table2_segs);
    for (table2_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // Padding - wrap content in a styled background to show padding
    try stdout.writeAll("\nPadding (uniform=1, with background):\n");
    const pad_content = [_]rich.Segment{rich.Segment.plain("Padded")};
    const bg_style = rich.Style.empty.background(rich.Color.fromRgb(60, 60, 80));
    const padding = rich.Padding.init(&pad_content).uniform(1).withStyle(bg_style);
    const pad_segs = try padding.render(20, allocator);
    defer allocator.free(pad_segs);
    for (pad_segs) |seg| {
        try seg.render(stdout, .truecolor);
    }

    // Align - horizontal alignment within a width
    try stdout.writeAll("\nAlign (width=20, showing left/center/right):\n");
    const align_content = [_]rich.Segment{rich.Segment.plain("Text")};

    try stdout.writeAll("|");
    const align_left = rich.Align.init(&align_content).left().withWidth(20);
    const align_left_segs = try align_left.render(80, allocator);
    defer allocator.free(align_left_segs);
    for (align_left_segs) |seg| {
        if (!std.mem.eql(u8, seg.text, "\n")) try seg.render(stdout, .truecolor);
    }
    try stdout.writeAll("| left\n");

    try stdout.writeAll("|");
    const aligned = rich.Align.init(&align_content).center().withWidth(20);
    const align_segs = try aligned.render(80, allocator);
    defer allocator.free(align_segs);
    for (align_segs) |seg| {
        if (!std.mem.eql(u8, seg.text, "\n")) try seg.render(stdout, .truecolor);
    }
    try stdout.writeAll("| center\n");

    try stdout.writeAll("|");
    const align_right = rich.Align.init(&align_content).right().withWidth(20);
    const align_right_segs = try align_right.render(80, allocator);
    defer allocator.free(align_right_segs);
    for (align_right_segs) |seg| {
        if (!std.mem.eql(u8, seg.text, "\n")) try seg.render(stdout, .truecolor);
    }
    try stdout.writeAll("| right\n");

    // Console log methods - flush our buffer first so log output appears in order
    try stdout.writeAll("\nConsole logging:\n");
    try stdout.flush();
    try console.logDebug("This is a debug message", .{});
    try console.logInfo("This is an info message", .{});
    try console.logWarn("This is a warning message", .{});
    try console.logErr("This is an error message", .{});

    try stdout.writeAll("\nAll phases complete!\n");
    try stdout.flush();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
